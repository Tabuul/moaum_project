-- ═══════════════════════════════════════
-- V616 — a spillover student pays a semester's school fees only when they register a course in that semester
--
--   The University's rule of 21 October 2026: a student in spillover pays for a semester only when they choose to register a course
--   in it. Until now a spillover student was charged every spillover line of the session's open semesters (V088, V571, V613), so one
--   with an outstanding course in the second semester alone still owed the first semester's line. Now, for a student in spillover
--   (finance.spill, on the basis the Bursary set): a fee line naming a semester applies once a course registration of theirs for
--   that session and semester holds a course (any state short of dropped — a draft counts: the choice is the charge), and a line for
--   the whole session applies once any semester of the session is so registered. Nothing changes for a student not in spillover.
--   - finance.reg_semesters(student, session) and finance.spill_line_applies(is_spill, line_semester, reg_sems) state the rule once;
--     charges_of_as (what is owed) and due_for_semester read it; charges_of_as takes a fifth argument, true for the lines that could
--     apply whether or not a semester is registered — fee_stated (lines exist) and fee_unstated_semesters (which open semesters have
--     no line) read those, so the register opens before the first course is chosen and nothing is reported unstated.
--   - finance.fee_profiles(session) carries each spillover student's registered semesters (NULL for every other student) in the
--     profile and its key, so fee_sums and the readers built on profiles — session_positions, session_charges, fee_positions_of,
--     registrations_without_fees — charge a spillover student as the student's own position does; fee_profiles() with no argument
--     reads the University's current session. The per-student keys of fee_positions_of and registrations_without_fees now carry the
--     spillover year (V613) and the registered semesters, so two spillover students of one level and year are told apart.
--   - registration.student_add no longer holds a spillover student's course for the Bursary's clearance: the choice makes the fee
--     due, and the submission waits for the payment (registration.submit_checks, unchanged).
--   The student's fees page says so; the Fee Setup, the gap report and every line stated are untouched.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V616: a spillover student pays a semester''s school fees only when they register a course in it', true);

-- the semesters of a session a student has registered a course in: a registration holding a course not dropped, in any state
CREATE OR REPLACE FUNCTION finance.reg_semesters(p_student uuid, p_session text)
 RETURNS integer[]
 LANGUAGE sql
 STABLE
AS $function$
    SELECT coalesce(array_agg(DISTINCT cr.semester ORDER BY cr.semester), '{}'::int[])
      FROM registration.course_registration cr
     WHERE cr.student_id = p_student AND cr.session = p_session
       AND EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN'))
$function$;
COMMENT ON FUNCTION finance.reg_semesters(uuid, text) IS 'V616: the semesters of the session the student has registered a course in — a registration in any state holding a course not dropped; a spillover student''s fee lines are read against it';

-- whether a fee line reaches a student given their spillover state and registered semesters: everyone not in spillover as before;
-- a spillover student a semester's line once that semester is registered, a whole-session line once any is
CREATE OR REPLACE FUNCTION finance.spill_line_applies(p_is_spill boolean, p_line_semester integer, p_reg_sems integer[])
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT NOT coalesce(p_is_spill, false)
        OR CASE WHEN p_line_semester IS NULL THEN cardinality(coalesce(p_reg_sems, '{}'::int[])) > 0
                ELSE p_line_semester = ANY (coalesce(p_reg_sems, '{}'::int[])) END
$function$;
COMMENT ON FUNCTION finance.spill_line_applies(boolean, integer, integer[]) IS 'V616: a spillover student is charged a semester''s line once they register a course in that semester, a whole-session line once any semester is registered; a student not in spillover is charged as before';

-- what is owed, and the lines that could apply (the fifth argument): the old signature dropped, its callers unchanged
DROP FUNCTION finance.charges_of_as(uuid, text, text[], text);
CREATE OR REPLACE FUNCTION finance.charges_of_as(p_student uuid, p_session text, p_kinds text[], p_programme text, p_any_semester boolean DEFAULT false)
 RETURNS TABLE(id uuid, item text, amount numeric, ord integer)
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS MATERIALIZED (   -- V451: read once, not once per fee line
        SELECT s.id, coalesce(p_programme, s.programme_code) AS programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
               finance.spill(s.id, s.current_level, coalesce(p_programme, s.programme_code), s.status) AS is_spill,
               finance.spill_year(s.id, s.current_level, coalesce(p_programme, s.programme_code), s.status) AS spill_year,   -- V613: SP1, SP2, SP3 (NULL when not in spillover)
               finance.final_level(coalesce(p_programme, s.programme_code)) AS final_level,   -- V613: the level a spillover line names
               finance.reg_semesters(s.id, p_session) AS reg_sems,   -- V616: the semesters the student has registered a course in
               (SELECT finance.fee_source_of(pp.faculty_code, p_session) FROM ref.programme pp
                 WHERE pp.code = coalesce(p_programme, s.programme_code) AND s.entry_mode IS DISTINCT FROM 'CCE'
                   AND NOT people.is_postgraduate(s.entry_mode, pp.category)) AS src   -- V451: the faculty charged as, while a rule is in force
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.id = p_student)
    SELECT f.id,
           replace(replace(replace(f.item,
               '(semester 1)', '(First Semester)'),
               '(semester 2)', '(Second Semester)'),
               '(semester 3)', '(Third Semester)') AS item,
           f.amount, f.ord
      FROM finance.fee_schedule f
      CROSS JOIN me
      JOIN ref.programme p ON p.code = me.programme_code
      LEFT JOIN ref.fee_group g ON g.code = f.fee_group
      CROSS JOIN home
     WHERE f.session = p_session AND f.ended_at IS NULL
       AND f.kind = ANY (p_kinds)
       AND f.spillover = me.is_spill
       AND (f.level IS NULL OR f.level = CASE WHEN me.is_spill THEN me.final_level ELSE me.current_level END)   -- V613: on a spillover line the level is the programme's final level
       AND (f.spill_year IS NULL OR f.spill_year = me.spill_year)   -- V613: SP1, SP2, SP3, or any spillover year
       AND (p_any_semester OR finance.spill_line_applies(me.is_spill, f.semester, me.reg_sems))   -- V616: a spillover student is charged a semester's line once they register a course in it; a whole-session line once any
       AND ((f.entry_mode IS NULL AND me.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = me.entry_mode)   -- V379: a line naming no entry mode never reaches a CCE student
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code OR (f.faculty_code = me.src AND f.programme_code IS NULL))
       AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND finance.pg_line(me.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, g.applies_category)   -- V391: a full-time line never reaches a postgraduate student
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)))
       AND (f.semester IS NULL
            OR f.semester <= coalesce((SELECT max(sm.number) FROM policy.semester sm
                                        WHERE sm.session = p_session AND sm.state = 'OPEN'), 3))
     ORDER BY f.ord, f.item;
$function$;

CREATE OR REPLACE FUNCTION finance.due_for_semester(p_student uuid, p_session text, p_semester integer)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS MATERIALIZED (   -- V451: read once, not once per fee line
        SELECT s.id, s.programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
               finance.spill(s.id, s.current_level, s.programme_code, s.status) AS is_spill,
               finance.spill_year(s.id, s.current_level, s.programme_code, s.status) AS spill_year,   -- V613: SP1, SP2, SP3 (NULL when not in spillover)
               finance.final_level(s.programme_code) AS final_level,   -- V613: the level a spillover line names
               finance.reg_semesters(s.id, p_session) AS reg_sems,   -- V616
               (SELECT finance.fee_source_of(pp.faculty_code, p_session) FROM ref.programme pp
                 WHERE pp.code = s.programme_code AND s.entry_mode IS DISTINCT FROM 'CCE'
                   AND NOT people.is_postgraduate(s.entry_mode, pp.category)) AS src   -- V451: the faculty charged as, while a rule is in force
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.id = p_student)
    SELECT coalesce(sum(f.amount), 0)
      FROM finance.fee_schedule f
      CROSS JOIN me
      JOIN ref.programme p ON p.code = me.programme_code
      LEFT JOIN ref.fee_group g ON g.code = f.fee_group
      CROSS JOIN home
     WHERE f.session = p_session AND f.ended_at IS NULL
       AND f.spillover = me.is_spill
       AND (f.level IS NULL OR f.level = CASE WHEN me.is_spill THEN me.final_level ELSE me.current_level END)   -- V613: on a spillover line the level is the programme's final level
       AND (f.spill_year IS NULL OR f.spill_year = me.spill_year)   -- V613: SP1, SP2, SP3, or any spillover year
       AND finance.spill_line_applies(me.is_spill, f.semester, me.reg_sems)   -- V616: a spillover student is charged a semester's line once they register a course in it; a whole-session line once any
       AND ((f.entry_mode IS NULL AND me.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = me.entry_mode)   -- V379: a line naming no entry mode never reaches a CCE student
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code OR (f.faculty_code = me.src AND f.programme_code IS NULL))
       AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND finance.pg_line(me.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, g.applies_category)   -- V391: a full-time line never reaches a postgraduate student
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)))
       AND (f.semester IS NULL OR f.semester <= p_semester);
$function$;

CREATE OR REPLACE FUNCTION finance.fee_unstated_semesters(p_student uuid, p_session text)
 RETURNS integer[]
 LANGUAGE sql
 STABLE
AS $function$
    WITH me AS (SELECT s.entry_mode, p.category FROM people.student s JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = p_student),
    -- V616: the lines that could apply to the student, registered in the semester or not
    lines AS (SELECT f.semester FROM finance.charges_of_as(p_student, p_session, ARRAY['FEE'], NULL, true) c JOIN finance.fee_schedule f ON f.id = c.id)
    SELECT CASE
        WHEN NOT EXISTS (SELECT 1 FROM me) THEN '{}'::int[]
        WHEN (SELECT me.entry_mode IS NOT DISTINCT FROM 'CCE' OR people.is_postgraduate(me.entry_mode, me.category) FROM me) THEN '{}'::int[]
        WHEN p_session < coalesce(finance.schedule_from(), p_session) THEN '{}'::int[]
        WHEN NOT EXISTS (SELECT 1 FROM lines) THEN '{}'::int[]
        WHEN EXISTS (SELECT 1 FROM lines l WHERE l.semester IS NULL) THEN '{}'::int[]
        ELSE coalesce((SELECT array_agg(sm.number ORDER BY sm.number) FROM policy.semester sm
                        WHERE sm.session = p_session AND sm.state = 'OPEN'
                          AND NOT EXISTS (SELECT 1 FROM lines l WHERE l.semester = sm.number)), '{}'::int[]) END
$function$;

-- the profiles, for the session asked (the return type changes: dropped and made again; the readers below name the session)
DROP FUNCTION finance.fee_profiles();
CREATE OR REPLACE FUNCTION finance.fee_profiles(p_session text)
 RETURNS TABLE(student_id uuid, status text, programme_code text, faculty_code text, category text, current_level integer, entry_mode text, state text, is_spill boolean, spill_year integer, final_level integer, reg_sems integer[], profile_key text)
 LANGUAGE sql
 STABLE
AS $function$
    -- V537: each programme's final level read once (456 calls), not twice for every student: on a connection the portal has
    -- used a while, PostgreSQL 18 reads finance.final_level by a cached generic plan that costs about seven times as much a call
    WITH fl AS MATERIALIZED (SELECT pr.code, finance.final_level(pr.code) AS final FROM ref.programme pr),
    -- V571: the Bursary's basis for the spillover lines, read once (LEVEL: above the final level; COHORT: the cohort engine's spillover)
    basis AS MATERIALIZED (SELECT finance.spill_basis() AS b),
    -- V616: the semesters each student has registered a course in, for the session asked — read once over the session's registrations
    regs AS MATERIALIZED (
        SELECT cr.student_id, array_agg(DISTINCT cr.semester ORDER BY cr.semester) AS sems
          FROM registration.course_registration cr
         WHERE cr.session = p_session AND EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN'))
         GROUP BY cr.student_id)
    SELECT s.id, s.status, s.programme_code, p.faculty_code, p.category, s.current_level, s.entry_mode,
           lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
           (s.status <> 'GRADUATED' AND CASE WHEN basis.b = 'COHORT' THEN coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
                                                ELSE coalesce(s.current_level > fl.final, false) END) AS is_spill,
           CASE WHEN s.status = 'GRADUATED' THEN NULL
                WHEN basis.b = 'COHORT' THEN CASE WHEN ap.spillover_state LIKE 'SPILLOVER%' THEN least(greatest(coalesce(ap.spillover_years, 1), 1), 3) END
                WHEN s.current_level > fl.final THEN least((s.current_level - fl.final) / 100, 3) END AS spill_year,   -- V613
           fl.final AS final_level,   -- V613
           CASE WHEN s.status <> 'GRADUATED' AND CASE WHEN basis.b = 'COHORT' THEN coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
                                                    ELSE coalesce(s.current_level > fl.final, false) END
                THEN coalesce(rg.sems, '{}'::int[]) END AS reg_sems,   -- V616: NULL for a student not in spillover
           concat_ws('|', s.programme_code, s.current_level, s.entry_mode,
                     lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))),
                     (s.status <> 'GRADUATED' AND CASE WHEN basis.b = 'COHORT' THEN coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
                                                ELSE coalesce(s.current_level > fl.final, false) END),
                     CASE WHEN s.status = 'GRADUATED' THEN NULL
                          WHEN basis.b = 'COHORT' THEN CASE WHEN ap.spillover_state LIKE 'SPILLOVER%' THEN least(greatest(coalesce(ap.spillover_years, 1), 1), 3) END
                          WHEN s.current_level > fl.final THEN least((s.current_level - fl.final) / 100, 3) END,
                     CASE WHEN s.status <> 'GRADUATED' AND CASE WHEN basis.b = 'COHORT' THEN coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
                                                              ELSE coalesce(s.current_level > fl.final, false) END
                          THEN coalesce(rg.sems, '{}'::int[])::text END) AS profile_key   -- V613: the spillover year, V616: the registered semesters, are part of a spillover profile
      FROM people.student s
      JOIN ref.programme p ON p.code = s.programme_code
      JOIN fl ON fl.code = s.programme_code
      CROSS JOIN basis
      LEFT JOIN people.academic_position ap ON ap.student_id = s.id
      LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
      LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
      LEFT JOIN regs rg ON rg.student_id = s.id
$function$;

CREATE OR REPLACE FUNCTION finance.fee_profiles()
 RETURNS TABLE(student_id uuid, status text, programme_code text, faculty_code text, category text, current_level integer, entry_mode text, state text, is_spill boolean, spill_year integer, final_level integer, reg_sems integer[], profile_key text)
 LANGUAGE sql
 STABLE
AS $function$
    SELECT * FROM finance.fee_profiles(policy.university_current_session())
$function$;
COMMENT ON FUNCTION finance.fee_profiles() IS 'V524, V613, V616: the fee profiles for the University''s current session — finance.fee_profiles(session) names the session';

CREATE OR REPLACE FUNCTION finance.fee_sums(p_session text, p_semester integer)
 RETURNS TABLE(profile_key text, due_before numeric, due_upto numeric, fee numeric, late_payment numeric, late_registration numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT lower(home_state) AS home_state FROM finance.fee_setting WHERE id = 1),
    open_max AS (SELECT coalesce((SELECT max(sm.number) FROM policy.semester sm WHERE sm.session = p_session AND sm.state = 'OPEN'), 3) AS n),
    prof AS (SELECT x.*, fs.source_code AS src   -- V451: the faculty a profile is charged as, while a rule is in force
               FROM (SELECT DISTINCT pr.profile_key, pr.programme_code, pr.faculty_code, pr.category, pr.current_level, pr.entry_mode, pr.state, pr.is_spill, pr.spill_year, pr.final_level, pr.reg_sems
                       FROM finance.fee_profiles(p_session) pr) x
               LEFT JOIN finance.fee_sources(p_session) fs ON fs.faculty_code = x.faculty_code AND x.entry_mode IS DISTINCT FROM 'CCE' AND NOT people.is_postgraduate(x.entry_mode, x.category)),
    matched AS (
        SELECT pr.profile_key, f.kind, f.semester, f.amount
          FROM prof pr
          CROSS JOIN home
          JOIN finance.fee_schedule f ON f.session = p_session AND f.ended_at IS NULL
          LEFT JOIN ref.fee_group g ON g.code = f.fee_group
         WHERE f.spillover = pr.is_spill
           AND (f.level IS NULL OR f.level = CASE WHEN pr.is_spill THEN pr.final_level ELSE pr.current_level END)   -- V613: on a spillover line the level is the programme's final level
           AND (f.spill_year IS NULL OR f.spill_year = pr.spill_year)   -- V613: SP1, SP2, SP3, or any spillover year
           AND finance.spill_line_applies(pr.is_spill, f.semester, coalesce(pr.reg_sems, '{}'::int[]))   -- V616: a spillover student is charged a semester's line once they register a course in it; a whole-session line once any
           AND ((f.entry_mode IS NULL AND pr.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = pr.entry_mode)   -- V379
           AND (f.faculty_code IS NULL OR f.faculty_code = pr.faculty_code OR (f.faculty_code = pr.src AND f.programme_code IS NULL))
           AND (f.programme_code IS NULL OR f.programme_code = pr.programme_code)
           AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = pr.category)
           AND finance.pg_line(pr.entry_mode = 'POSTGRADUATE' OR pr.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, g.applies_category)   -- V391: a full-time line never reaches a postgraduate student
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
$function$;

CREATE OR REPLACE FUNCTION finance.session_positions(p_session text, p_semester integer)
 RETURNS TABLE(student_id uuid, payable numeric, paid numeric, outstanding numeric, status text, last_paid_at timestamp with time zone, last_reference text, last_channel text, payments integer, cleared_upto boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH prof AS MATERIALIZED (SELECT fp.student_id, fp.profile_key FROM finance.fee_profiles(p_session) fp),
    sums AS MATERIALIZED (SELECT s.profile_key, s.due_before, s.due_upto FROM finance.fee_sums(p_session, p_semester) s),
    pay AS MATERIALIZED (SELECT p.* FROM finance.session_payments(p_session) p),
    pos AS (
        SELECT pr.student_id,
               greatest(coalesce(s.due_upto, 0) - coalesce(s.due_before, 0), 0) AS payable,
               least(greatest(coalesce(pay.total, 0) - coalesce(s.due_before, 0), 0),
                     greatest(coalesce(s.due_upto, 0) - coalesce(s.due_before, 0), 0)) AS applied,
               coalesce(pay.total, 0) AS paid_all, coalesce(pay.n, 0) AS n,
               coalesce(s.due_upto, 0) AS upto,
               pay.last_paid_at, pay.last_reference, pay.last_channel
          FROM prof pr
          LEFT JOIN sums s ON s.profile_key = pr.profile_key
          LEFT JOIN pay ON pay.student_id = pr.student_id),
    judged AS (SELECT pos.*, CASE WHEN p_semester IS NULL THEN pos.paid_all ELSE pos.applied END AS paid_now FROM pos)
    SELECT j.student_id, j.payable, j.paid_now,
           finance.fee_owed(j.payable, j.paid_now),
           CASE WHEN j.payable = 0 THEN 'NO_CHARGE'
                WHEN NOT finance.fee_short(j.payable, j.paid_now) THEN 'FULLY_PAID'
                WHEN j.paid_now > 0 THEN 'PART_PAYMENT'
                ELSE 'NOT_PAID' END,
           j.last_paid_at, j.last_reference, j.last_channel, j.n,
           NOT finance.fee_short(j.upto, j.paid_all)
      FROM judged j
$function$;

CREATE OR REPLACE FUNCTION finance.session_charges(p_session text)
 RETURNS TABLE(student_id uuid, fee numeric, late_payment boolean, late_registration boolean, total numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH w AS MATERIALIZED (SELECT * FROM policy.window_state('SCHOOL_FEES_PAYMENT', p_session, NULL)),
    -- V537: read once, not inside the check made for every student
    reg_windows AS MATERIALIZED (
        SELECT sem, rw.phase, rw.closes_at
          FROM generate_series(1, 3) sem
          CROSS JOIN LATERAL policy.window_state('COURSE_REGISTRATION', p_session, sem) rw
         WHERE rw.configured AND rw.late_fee_enabled),
    paid_in_time AS MATERIALIZED (
        SELECT r.student_id, sum(r.amount) AS total
          FROM finance.payment_reference r CROSS JOIN w
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.purpose LIKE 'School fees%'
           AND (w.closes_at IS NULL OR r.confirmed_at <= w.closes_at)
         GROUP BY r.student_id),
    prof AS MATERIALIZED (SELECT fp.student_id, fp.profile_key FROM finance.fee_profiles(p_session) fp),
    sums AS MATERIALIZED (SELECT x.profile_key, x.fee, x.late_payment, x.late_registration FROM finance.fee_sums(p_session, NULL) x),
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
          FROM prof pr
          LEFT JOIN sums s ON s.profile_key = pr.profile_key
          LEFT JOIN paid_in_time pit ON pit.student_id = pr.student_id)
    SELECT e.student_id, e.fee, coalesce(e.late_payment, false), e.late_registration,
           e.fee + CASE WHEN coalesce(e.late_payment, false) THEN e.lp ELSE 0 END + CASE WHEN e.late_registration THEN e.lr ELSE 0 END
      FROM each e
$function$;

CREATE OR REPLACE FUNCTION finance.fee_positions_of(p_session text, p_students uuid[])
 RETURNS TABLE(student_id uuid, stated boolean, due numeric, paid numeric, balance numeric, instalments_paid integer, paid_in_full boolean, has_arrears boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH them AS MATERIALIZED (SELECT DISTINCT x AS id FROM unnest(p_students) x WHERE x IS NOT NULL),
    prof AS MATERIALIZED (   -- the fee schedule's answers depend only on the fee profile (V524)
        SELECT t.id AS student_id,
               CASE WHEN fp.student_id IS NULL THEN t.id::text
                    ELSE row(fp.programme_code, fp.current_level, fp.entry_mode, fp.state, fp.is_spill, fp.spill_year, fp.reg_sems)::text END AS k   -- V613/V616: the year and the registered semesters tell spillover profiles apart
          FROM them t LEFT JOIN finance.fee_profiles(p_session) fp ON fp.student_id = t.id),
    said AS MATERIALIZED (
        SELECT r.k, finance.fee_stated(r.student_id, p_session) AS stated
          FROM (SELECT DISTINCT ON (p.k) p.k, p.student_id FROM prof p ORDER BY p.k, p.student_id) r),
    pos AS MATERIALIZED (SELECT f.* FROM finance.session_fee_positions(p_session) f WHERE f.student_id IN (SELECT t.id FROM them t))
    SELECT pf.student_id, sd.stated, coalesce(p.due, 0), coalesce(p.paid, 0), coalesce(p.balance, 0), coalesce(p.instalments_paid, 2),
           coalesce(p.paid_in_full, true), coalesce(p.has_arrears, false)
      FROM prof pf JOIN said sd ON sd.k = pf.k LEFT JOIN pos p ON p.student_id = pf.student_id
$function$;

CREATE OR REPLACE FUNCTION finance.registrations_without_fees(p_session text)
 RETURNS TABLE(registration_id uuid, student_id uuid, number text, name text, programme text, faculty text, level integer, semester integer, status text, submitted_at timestamp with time zone, approved_at timestamp with time zone, stated boolean, due numeric, paid numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH reg AS MATERIALIZED (
        SELECT r.id, r.student_id, r.session, r.level, r.semester, r.status, r.submitted_at, r.approved_at
          FROM registration.course_registration r
         WHERE r.session = p_session AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')),
    -- V524: the fee profile of each registered student (what the schedule's answers depend on)
    prof AS MATERIALIZED (
        SELECT DISTINCT r.student_id,
               CASE WHEN fp.student_id IS NULL THEN r.student_id::text
                    ELSE row(fp.programme_code, fp.current_level, fp.entry_mode, fp.state, fp.is_spill, fp.spill_year, fp.reg_sems)::text END AS k   -- V613/V616
          FROM reg r LEFT JOIN finance.fee_profiles(p_session) fp ON fp.student_id = r.student_id),
    rep AS MATERIALIZED (SELECT DISTINCT ON (p.k) p.k, p.student_id FROM prof p ORDER BY p.k, p.student_id),
    said AS MATERIALIZED (
        SELECT rp.k, finance.fee_stated(rp.student_id, p_session) AS stated,
               finance.fee_unstated_semesters(rp.student_id, p_session) AS unstated
          FROM rep rp),
    owed AS MATERIALIZED (
        SELECT ks.k, ks.semester, finance.due_for_semester(rp.student_id, p_session, ks.semester) AS due
          FROM (SELECT DISTINCT p.k, r.semester FROM reg r JOIN prof p ON p.student_id = r.student_id) ks
          JOIN rep rp ON rp.k = ks.k),
    paid AS MATERIALIZED (
        SELECT pr.student_id, sum(pr.amount) AS paid
          FROM finance.payment_reference pr
         WHERE pr.session = p_session AND pr.confirmed_at IS NOT NULL AND pr.purpose LIKE 'School fees%'
           AND pr.student_id IN (SELECT p.student_id FROM prof p)
         GROUP BY pr.student_id),
    open_ AS (SELECT coalesce(array_agg(sm.number), '{}'::int[]) AS n FROM policy.semester sm WHERE sm.session = p_session AND sm.state = 'OPEN')
    SELECT r.id, s.id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, p.name, f.name, r.level, r.semester,
           r.status, r.submitted_at, r.approved_at, sd.stated,
           CASE WHEN sd.stated THEN ow.due END,
           coalesce(pd.paid, 0)
      FROM reg r
      JOIN people.student s ON s.id = r.student_id
      LEFT JOIN ref.programme p ON p.code = s.programme_code
      LEFT JOIN ref.faculty f ON f.code = p.faculty_code
      JOIN prof pf ON pf.student_id = r.student_id
      JOIN said sd ON sd.k = pf.k
      JOIN owed ow ON ow.k = pf.k AND ow.semester = r.semester
      LEFT JOIN paid pd ON pd.student_id = r.student_id
      CROSS JOIN open_ o
     -- not cleared, as finance.semester_cleared decides it
     WHERE NOT (sd.stated
                AND NOT finance.fee_short(ow.due, coalesce(pd.paid, 0))
                AND NOT (r.semester = ANY (o.n) AND r.semester = ANY (sd.unstated)))
     ORDER BY f.name, p.name, s.surname, s.other_names, r.semester
$function$;

-- the add door
CREATE OR REPLACE FUNCTION registration.student_add(p_student uuid, p_session text, p_semester integer, p_offering uuid)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE r registration.course_registration; m record; lim policy.level_limit; v_units int; v_type text; v_status text; v_gate text; v_unmet text[];
        v_code text; x record; v_as text;
BEGIN
    SELECT * INTO r FROM registration.course_registration WHERE student_id = p_student AND session = p_session AND semester = p_semester;
    IF NOT FOUND THEN RAISE EXCEPTION 'register first, then add or drop' USING ERRCODE = '23514'; END IF;
    IF r.status = 'LOCKED' THEN RAISE EXCEPTION 'this registration is locked and cannot be changed' USING ERRCODE = '23514'; END IF;
    IF NOT registration.add_drop_open(p_student, p_session, p_semester) THEN   -- V380: by the student's calendar
        RAISE EXCEPTION 'add and drop is not open for % semester %', p_session, p_semester USING ERRCODE = '23514',
            HINT = 'It runs while the semester is open, up to the late-registration deadline set by the Registry.';
    END IF;
    -- V616: a spillover student's choice of courses is what makes the semester's fee due, so the choice is not held for the
    -- payment; the submission waits for it (submit_checks reads finance.semester_cleared) as for everyone
    IF NOT finance.clears(p_student, p_session, 'REGISTRATION') AND NOT finance.is_spillover(p_student) THEN
        RAISE EXCEPTION 'the Bursary has not cleared you for registration in %', p_session USING ERRCODE = '23514';
    END IF;
    -- V504: a course already on the registration is not added twice
    SELECT o.course_code INTO v_code FROM catalogue.offering o WHERE o.id = p_offering;
    IF EXISTS (SELECT 1 FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id
                WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN') AND o.course_code = v_code) THEN
        RAISE EXCEPTION 'REG_ALREADY_ADDED: Course already added' USING ERRCODE = '23514';
    END IF;

    SELECT * INTO m FROM registration.student_menu(p_student, p_session, p_semester) WHERE offering_id = p_offering AND NOT carryover;
    IF FOUND THEN
        -- V314: a GST or EPS course is added only by a student whose GST fee is paid
        v_gate := registration.gst_gate(p_student, p_session, m.course_code);
        IF v_gate IS NOT NULL THEN
            RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; it opens the moment the payment is confirmed.';
        END IF;
        -- V482: where the Academic Office enforces prerequisites, a course whose prerequisite the student has not passed is refused
        IF registration.prerequisite_mode() = 'ENFORCED' THEN
            v_unmet := registration.prerequisites_unmet(p_student, m.course_code);
            IF cardinality(v_unmet) > 0 THEN
                RAISE EXCEPTION 'REG_PREREQUISITE: % needs % passed first; no published pass is on your record', m.course_code, array_to_string(v_unmet, ', ')
                    USING ERRCODE = '23514', HINT = 'If you passed it and the result is not yet published, or were exempted, your department asks ICT Support to add the course on your ticket.';
            END IF;
        END IF;
        v_units := m.units;
        v_type := CASE WHEN m.basis = 'GST' OR m.kind = 'GST' THEN 'GST' WHEN m.basis = 'Borrowed' THEN 'BORROWED'
                       WHEN m.basis = 'Elective' OR (m.basis IS NULL AND m.kind = 'Elective') THEN 'ELECTIVE' ELSE 'CURRENT' END;
    ELSE
        -- V504: a course beside the menu, when the engine allows it (registration.course_check judges it; prerequisites included)
        SELECT * INTO x FROM registration.course_refusal(p_student, p_session, p_semester, p_offering);
        IF x.refusal IS NOT NULL THEN RAISE EXCEPTION '%', x.refusal USING ERRCODE = '23514'; END IF;
        -- V314: the GST fee owed holds every course the student registers, as on the menu (registration.gst_gate)
        v_gate := registration.gst_gate(p_student, p_session, v_code);
        IF v_gate IS NOT NULL THEN
            RAISE EXCEPTION '%', v_gate USING ERRCODE = '23514', HINT = 'Pay the GST fee on GST & EPS; it opens the moment the payment is confirmed.';
        END IF;
        SELECT catalogue.units_for(v_code, s.programme_code, NULL) INTO v_units FROM people.student s WHERE s.id = p_student;
        v_type := CASE x.category WHEN 'CARRY_OVER' THEN 'CARRYOVER' WHEN 'GST' THEN 'GST' WHEN 'ELECTIVE' THEN 'ELECTIVE' ELSE 'CURRENT' END;
        v_as := x.added_as;
    END IF;
    -- an approved registration has no further approval step, so the added course is examinable at once;
    -- a still-submitted one keeps REGISTERED and the HOD's approval flips it with the batch (RegistrationRepository)
    v_status := CASE WHEN r.status = 'APPROVED' THEN 'APPROVED' ELSE 'REGISTERED' END;

    -- would this exceed the level's maximum?
    SELECT * INTO lim FROM registration.unit_limit(p_student, r.level);   -- V380: the CCE course load for a CCE student
    IF FOUND AND registration.units_of(r.id) + v_units > lim.max_units THEN
        RAISE EXCEPTION 'adding this course puts you at % units, over the maximum of % at % level',
            registration.units_of(r.id) + v_units, lim.max_units, r.level USING ERRCODE = '23514',
            HINT = 'Drop a course first, or ask your Head of Department for an overload.';
    END IF;

    -- reinstate a dropped entry, or add a new one
    IF EXISTS (SELECT 1 FROM registration.entry WHERE registration_id = r.id AND offering_id = p_offering) THEN
        UPDATE registration.entry SET status = v_status, units = v_units, entry_type = v_type,
               student_added_at = CASE WHEN m.offering_id IS NULL THEN now() END, added_as = v_as
         WHERE registration_id = r.id AND offering_id = p_offering;
    ELSE
        INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status, student_added_at, added_as)
        VALUES (r.id, p_offering, v_units, v_type, v_status, CASE WHEN m.offering_id IS NULL THEN now() END, v_as);
    END IF;
    PERFORM registration.gst_course_registered(r.id, p_offering);   -- V512: the GST/EPS registration log
    RETURN registration.units_of(r.id);
END $function$;

COMMENT ON FUNCTION finance.charges_of_as(uuid, text, text[], text, boolean) IS
    'what a student is charged for a session, line by line, as the programme named (V451 charged-as rule, V391 PG lines, V571 spillover basis, V613 spillover year, V616: a spillover student''s semester lines once the semester is registered — the fifth argument true reads the lines that could apply whether or not it is)';
COMMENT ON FUNCTION finance.fee_profiles(text) IS
    'V524, V613, V616: each student''s fee profile — programme, level, entry mode, state of origin, spillover with its year and final level, and (a spillover student''s) the semesters registered in the session asked — and the key the schedule''s answers depend on';

COMMIT;
