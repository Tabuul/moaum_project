-- ═══════════════════════════════════════
-- V637 — SP1/SP2 at the final level billed as spillover: a semester's spillover fee for each semester registered, never a full session
--
--   The University's brief of 22 October 2026 (semester-based spillover school fees, SP1/SP2 billing and carry-over registration):
--   "a spillover student does not pay school fees for the entire session again simply because the student is in SP1 or SP2; the
--   student pays only for the semester(s) in which the student has outstanding carry-over courses". Its answers: SP1/SP2 students at
--   the final level are billed as spillover, from 2025/2026 (the current session).
--
--   What already held: a spillover student owes a semester's spillover lines only once a course is registered in that semester, a
--   whole-session spillover line once any is (V616); the Bursary states spillover lines by semester and by SP year (V613: on the
--   live-shaped copy every 2025/2026 spillover line names a semester, 42 for each); carry-overs come from published results and are
--   registered below the minimum load (V597, V615); declared carry-overs from the old portal (V611).
--
--   What did not: who is in spillover for fees. Under the Bursary's LEVEL basis (V571, in force) a student was in spillover only
--   above the programme's final level — but since V628 the level desk sets SP1/SP2 by keeping the record AT the final level (400 on a
--   four-year programme) and pinning the expected completion, and the cohort engine counts the spillover year from it. So an SP1 or
--   SP2 student at 400 read as an ordinary final-year student and owed the full normal session on registering. On the live-shaped
--   copy: 564 students in study at their final level whom the cohort engine places in spillover (503 SP1, 10 SP2, 51 past the limit),
--   billed ₦47.0m as full sessions for 2025/2026; 201 of them paid ₦16.2m, which now reads as paid above what they owe (the Bursary's
--   overpaid desk carries or refunds it, V506) — the University chose to apply it from 2025/2026.
--
--   Now, under the LEVEL basis, a student is in spillover above the final level (as before) OR at the final level when the cohort
--   engine places them in spillover (SPILLOVER_YEAR_n or the limit reached); the SP year is the level's distance above the final level,
--   or at the final level the cohort engine's spillover years (1–3). One rule, restated wherever it is written: finance.spill,
--   finance.spill_year, finance.fee_profiles, finance.fee_gaps, finance.spill_basis_moves (each restated exactly as it stood, the
--   spillover test alone changed). The COHORT basis is unchanged. A student below the final level is never in spillover by level.
--
--   Also: finance.spillover_panel(student, session) — what the student's Fees page and dashboard show (SP year, each semester's
--   spillover fee, whether a course is registered in it, the carry-over courses by original session and semester, due, paid);
--   finance.spillover_students(session, …) — the Bursary's spillover list (SP year, registered semesters, carry-overs, due, paid,
--   owing, state). A spillover student's school-fees reference is named for what it pays (StudentPortalService: "School fees
--   2025/2026 · spillover (SP1) · first semester"), still a school-fees payment to every reader (LIKE 'School fees%').
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V637: SP1/SP2 at the final level billed as spillover (the University, 22 October 2026)', true);

-- ── 1 · the one spillover test (restated from V571/V613 with the final-level case) ──
CREATE OR REPLACE FUNCTION finance.spill(p_student uuid, p_level integer, p_programme text, p_status text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE WHEN coalesce(p_status, '') = 'GRADUATED' THEN false
                WHEN finance.spill_basis() = 'COHORT'
                    THEN coalesce((SELECT ap.spillover_state LIKE 'SPILLOVER%' FROM people.academic_position ap WHERE ap.student_id = p_student), false)
                -- V637: above the final level, or at it when the cohort engine places the student in spillover (SP1/SP2 as the level desk sets it)
                ELSE coalesce(p_level > finance.final_level(p_programme)
                              OR (p_level = finance.final_level(p_programme)
                                  AND (SELECT ap.spillover_state LIKE 'SPILLOVER%' FROM people.academic_position ap WHERE ap.student_id = p_student)), false) END
$function$;
COMMENT ON FUNCTION finance.spill(uuid, integer, text, text) IS 'V571, V637: whether a student is charged the spillover lines — by the cohort engine (COHORT basis) or by the level (LEVEL basis: above the programme''s final level, or at it when the cohort engine places the student in spillover, as the level desk sets SP1/SP2). Never a graduated record.';

CREATE OR REPLACE FUNCTION finance.spill_year(p_student uuid, p_level integer, p_programme text, p_status text)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE WHEN coalesce(p_status, '') = 'GRADUATED' THEN NULL
                WHEN finance.spill_basis() = 'COHORT'
                    THEN (SELECT CASE WHEN ap.spillover_state LIKE 'SPILLOVER%' THEN least(greatest(coalesce(ap.spillover_years, 1), 1), 3) END
                            FROM people.academic_position ap WHERE ap.student_id = p_student)
                WHEN p_level > finance.final_level(p_programme) THEN least((p_level - finance.final_level(p_programme)) / 100, 3)
                -- V637: at the final level, the cohort engine's spillover year
                WHEN p_level = finance.final_level(p_programme)
                    THEN (SELECT CASE WHEN ap.spillover_state LIKE 'SPILLOVER%' THEN least(greatest(coalesce(ap.spillover_years, 1), 1), 3) END
                            FROM people.academic_position ap WHERE ap.student_id = p_student)
                ELSE NULL END
$function$;
COMMENT ON FUNCTION finance.spill_year(uuid, integer, text, text) IS 'V613, V637: the spillover year a student is charged as (1–3) — the cohort engine''s, or the level''s distance above the final level, or at the final level the cohort engine''s; NULL when not in spillover.';

-- ── 2 · the readers that write the test out for every student at once (restated exactly, the test alone changed) ──
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
                                                ELSE coalesce(s.current_level > fl.final OR (s.current_level = fl.final AND ap.spillover_state LIKE 'SPILLOVER%'), false) END) AS is_spill,
           CASE WHEN s.status = 'GRADUATED' THEN NULL
                WHEN basis.b = 'COHORT' THEN CASE WHEN ap.spillover_state LIKE 'SPILLOVER%' THEN least(greatest(coalesce(ap.spillover_years, 1), 1), 3) END
                WHEN s.current_level > fl.final THEN least((s.current_level - fl.final) / 100, 3)
                     WHEN s.current_level = fl.final AND ap.spillover_state LIKE 'SPILLOVER%' THEN least(greatest(coalesce(ap.spillover_years, 1), 1), 3) END AS spill_year,   -- V613
           fl.final AS final_level,   -- V613
           CASE WHEN s.status <> 'GRADUATED' AND CASE WHEN basis.b = 'COHORT' THEN coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
                                                    ELSE coalesce(s.current_level > fl.final OR (s.current_level = fl.final AND ap.spillover_state LIKE 'SPILLOVER%'), false) END
                THEN coalesce(rg.sems, '{}'::int[]) END AS reg_sems,   -- V616: NULL for a student not in spillover
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

CREATE OR REPLACE FUNCTION finance.fee_gaps(p_session text)
 RETURNS TABLE(faculty_code text, faculty text, programme_code text, programme text, level integer, entry_mode text, indigene boolean, spillover boolean, spill_year integer, final_level integer, students bigint, charged_as text, stated boolean, missing integer[])
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT lower(home_state) AS home_state FROM finance.fee_setting WHERE id = 1),
    open_sem AS (SELECT coalesce(array_agg(sm.number ORDER BY sm.number), '{}'::int[]) AS nums
                   FROM policy.semester sm WHERE sm.session = p_session AND sm.state = 'OPEN'),
    -- V541/V542: held, so the final level is read once a programme; inlined, it was read for every student joined to it
    fl AS MATERIALIZED (SELECT pr.code, finance.final_level(pr.code) AS final FROM ref.programme pr),
    basis AS MATERIALIZED (SELECT finance.spill_basis() AS b),   -- V571
    live AS (
        SELECT s.programme_code, p.faculty_code, p.category, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) = (SELECT h.home_state FROM home h) AS indigene,
               CASE WHEN basis.b = 'COHORT' THEN coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
                    ELSE coalesce(s.current_level > fl.final OR (s.current_level = fl.final AND ap.spillover_state LIKE 'SPILLOVER%'), false) END AS is_spill,
               CASE WHEN s.status = 'GRADUATED' THEN NULL
                    WHEN basis.b = 'COHORT' THEN CASE WHEN ap.spillover_state LIKE 'SPILLOVER%' THEN least(greatest(coalesce(ap.spillover_years, 1), 1), 3) END
                    WHEN s.current_level > fl.final THEN least((s.current_level - fl.final) / 100, 3)
                     WHEN s.current_level = fl.final AND ap.spillover_state LIKE 'SPILLOVER%' THEN least(greatest(coalesce(ap.spillover_years, 1), 1), 3) END AS spill_year,   -- V613
               fl.final AS final_level
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code
          JOIN fl ON fl.code = s.programme_code
          CROSS JOIN basis
          LEFT JOIN people.academic_position ap ON ap.student_id = s.id
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
          FROM (SELECT l.programme_code, l.faculty_code, l.category, l.current_level, l.entry_mode, l.indigene, l.is_spill, l.spill_year, l.final_level, count(*) AS students
                  FROM live l
                 GROUP BY l.programme_code, l.faculty_code, l.category, l.current_level, l.entry_mode, l.indigene, l.is_spill, l.spill_year, l.final_level) a
          LEFT JOIN src fs ON fs.faculty_code = a.faculty_code),
    matched AS (
        SELECT g.programme_code, g.current_level, g.entry_mode, g.indigene, g.is_spill, g.spill_year, f.semester
          FROM grp g
          JOIN finance.fee_schedule f ON f.session = p_session AND f.ended_at IS NULL AND f.kind = 'FEE'
          LEFT JOIN ref.fee_group fg ON fg.code = f.fee_group
         WHERE f.spillover = g.is_spill
           AND (f.level IS NULL OR f.level = CASE WHEN g.is_spill THEN g.final_level ELSE g.current_level END)   -- V613
           AND (f.spill_year IS NULL OR f.spill_year = g.spill_year)   -- V613
           AND ((f.entry_mode IS NULL AND g.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = g.entry_mode)
           AND (f.faculty_code IS NULL OR f.faculty_code = g.faculty_code OR (f.faculty_code = g.src AND f.programme_code IS NULL))
           AND (f.programme_code IS NULL OR f.programme_code = g.programme_code)
           AND (f.fee_group IS NULL OR fg.applies_category IS NULL OR fg.applies_category = g.category)
           AND finance.pg_line(g.entry_mode = 'POSTGRADUATE' OR g.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, fg.applies_category)
           AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = g.indigene)),
    stated AS (
        SELECT m.programme_code, m.current_level, m.entry_mode, m.indigene, m.is_spill, m.spill_year,
               bool_or(m.semester IS NULL) AS whole,
               coalesce(array_agg(DISTINCT m.semester) FILTER (WHERE m.semester IS NOT NULL), '{}'::int[]) AS sems
          FROM matched m
         GROUP BY m.programme_code, m.current_level, m.entry_mode, m.indigene, m.is_spill, m.spill_year),
    judged AS (
        SELECT g.programme_code, g.faculty_code, g.current_level, g.entry_mode, g.indigene, g.is_spill, g.spill_year, g.final_level, g.students, g.src,
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
                             AND st.is_spill = g.is_spill
                             AND st.spill_year IS NOT DISTINCT FROM g.spill_year)
    SELECT j.faculty_code, fa.name, j.programme_code, p.name, j.current_level, j.entry_mode, j.indigene, j.is_spill, j.spill_year, j.final_level, j.students,
           j.src, j.has_line, j.missing
      FROM judged j
      JOIN ref.programme p ON p.code = j.programme_code
      LEFT JOIN ref.faculty fa ON fa.code = j.faculty_code
     WHERE NOT j.has_line OR cardinality(j.missing) > 0
     ORDER BY j.faculty_code, j.programme_code, j.current_level, j.entry_mode, j.indigene, j.is_spill, j.spill_year
$function$;

CREATE OR REPLACE FUNCTION finance.spill_basis_moves()
 RETURNS TABLE(student_id uuid, by_level boolean, by_cohort boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH fl AS MATERIALIZED (SELECT pr.code, finance.final_level(pr.code) AS final FROM ref.programme pr)
    SELECT s.id, coalesce(s.current_level > fl.final OR (s.current_level = fl.final AND ap.spillover_state LIKE 'SPILLOVER%'), false), coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
      FROM people.student s
      JOIN fl ON fl.code = s.programme_code
      LEFT JOIN people.academic_position ap ON ap.student_id = s.id
     WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
       AND coalesce(s.current_level > fl.final OR (s.current_level = fl.final AND ap.spillover_state LIKE 'SPILLOVER%'), false) IS DISTINCT FROM coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
$function$;

-- ── 3 · what the student's Fees page and dashboard show ──
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
    pos AS (SELECT * FROM finance.position(p_student, p_session))
    SELECT CASE WHEN NOT s.spill THEN NULL ELSE jsonb_build_object(
        'session', p_session,
        'state', (SELECT ap.spillover_state FROM ap),
        'year', s.yr,
        'label', CASE WHEN s.yr IS NOT NULL THEN 'SP' || s.yr ELSE 'Spillover' END,
        'registeredSemesters', to_jsonb(rs.sems),
        'semesters', (SELECT jsonb_agg(jsonb_build_object(
                          'semester', n,
                          'fee', coalesce((SELECT l.amount FROM lines l WHERE l.semester = n), 0),
                          'registered', n = ANY (rs.sems),
                          'carryovers', (SELECT count(*) FROM co WHERE co.semester = n),
                          'courses', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', co.course_code, 'title', co.title, 'units', co.units, 'session', co.session)
                                                                ORDER BY co.session, co.course_code), '[]'::jsonb) FROM co WHERE co.semester = n))
                          ORDER BY n) FROM unnest(ARRAY[1, 2]) n),
        'sessionFee', coalesce((SELECT l.amount FROM lines l WHERE l.semester IS NULL), 0),
        'due', pos.due, 'paid', pos.paid, 'balance', greatest(pos.balance, 0)) END
      FROM s CROSS JOIN rs CROSS JOIN pos
$function$;
COMMENT ON FUNCTION finance.spillover_panel(uuid, text) IS 'V637: a spillover student''s position for a session as the Fees page and the dashboard show it — the SP year, each semester''s spillover fee (as it applies once a course is registered in that semester) and whether one is, the carry-over courses by the session and semester they were failed in, any whole-session spillover line, due, paid, balance. NULL for a student not in spillover.';

-- ── 4 · the Bursary's spillover list ──
CREATE OR REPLACE FUNCTION finance.spillover_students(p_session text, p_fac text, p_dept text, p_prog text, p_year integer, p_state text, p_q text, p_limit integer DEFAULT 500)
 RETURNS TABLE(student_id uuid, student text, matric_no text, programme_code text, programme text, dept_code text, department text, faculty_code text, faculty text,
               level integer, final_level integer, spill_year integer, spillover_state text, registered_semesters integer[], carryovers integer,
               due numeric, paid numeric, owing numeric, state text, last_paid_at timestamp with time zone, last_reference text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH fp AS MATERIALIZED (
        SELECT x.* FROM finance.fee_profiles(p_session) x
         WHERE x.is_spill AND x.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')),
    pos AS MATERIALIZED (SELECT * FROM finance.session_positions(p_session, NULL)),
    j AS (
        SELECT fp.*, st.surname || ', ' || st.other_names AS name, coalesce(st.matric_no, st.admission_no) AS number,
               p.name AS prog_name, p.dept_code, d.name AS dept_name, f.name AS fac_name, ap.spillover_state AS cohort_state,
               coalesce(ps.payable, 0) AS payable, coalesce(ps.paid, 0) AS paid_amt, greatest(coalesce(ps.outstanding, 0), 0) AS outstanding,
               ps.last_paid_at, ps.last_reference,
               CASE WHEN coalesce(ps.paid, 0) > coalesce(ps.payable, 0) + 1 THEN 'PAID_ABOVE'
                    WHEN cardinality(coalesce(fp.reg_sems, '{}'::int[])) = 0 THEN 'NOT_REGISTERED'
                    WHEN coalesce(ps.payable, 0) = 0 THEN 'NO_CHARGE'
                    WHEN NOT finance.fee_short(ps.payable, ps.paid) THEN 'PAID'
                    WHEN coalesce(ps.paid, 0) > 0 THEN 'PART_PAID'
                    ELSE 'OWES' END AS st_state
          FROM fp
          JOIN people.student st ON st.id = fp.student_id
          JOIN ref.programme p ON p.code = fp.programme_code
          JOIN ref.department d ON d.code = p.dept_code
          JOIN ref.faculty f ON f.code = p.faculty_code
          LEFT JOIN people.academic_position ap ON ap.student_id = fp.student_id
          LEFT JOIN pos ps ON ps.student_id = fp.student_id
         WHERE (p_fac IS NULL OR p.faculty_code = p_fac)
           AND (p_dept IS NULL OR p.dept_code = p_dept)
           AND (p_prog IS NULL OR p.code = p_prog)
           AND (p_year IS NULL OR fp.spill_year = p_year)
           AND (p_q IS NULL OR btrim(p_q) = '' OR (st.surname || ' ' || st.other_names) ILIKE '%' || btrim(p_q) || '%'
                OR upper(coalesce(st.matric_no, '')) LIKE '%' || upper(btrim(p_q)) || '%'
                OR upper(coalesce(st.admission_no, '')) LIKE '%' || upper(btrim(p_q)) || '%'
                OR upper(coalesce(st.jamb_reg_no, '')) LIKE '%' || upper(btrim(p_q)) || '%')),
    picked AS (
        SELECT * FROM j WHERE p_state IS NULL OR j.st_state = p_state
         ORDER BY j.fac_name, j.dept_name, j.prog_name, j.name
         LIMIT greatest(1, least(coalesce(p_limit, 500), 5000)))
    SELECT pk.student_id, pk.name, pk.number, pk.programme_code, pk.prog_name, pk.dept_code, pk.dept_name, pk.faculty_code, pk.fac_name,
           pk.current_level, pk.final_level, pk.spill_year, pk.cohort_state, coalesce(pk.reg_sems, '{}'::int[]),
           (SELECT count(*) FROM registration.carryovers(pk.student_id))::int,
           pk.payable, pk.paid_amt, pk.outstanding, pk.st_state, pk.last_paid_at, pk.last_reference
      FROM picked pk
     ORDER BY pk.fac_name, pk.dept_name, pk.prog_name, pk.name
$function$;
COMMENT ON FUNCTION finance.spillover_students(text, text, text, text, integer, text, text, integer) IS 'V637: the Bursary''s spillover list for a session — every student in study charged the spillover lines, with the SP year, the semesters registered, the carry-overs the results state, due, paid, owing and where they stand (NOT_REGISTERED, NO_CHARGE, OWES, PART_PAID, PAID, PAID_ABOVE); by faculty, department, programme, SP year, state or search.';

COMMIT;
