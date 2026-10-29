-- V693: a postgraduate student past the maximum period is charged the last stage's fee line — the University's word of
-- 29 October 2026, on the Bursary's "7574 postgraduate students have no fee line stated for 2025/2026", the M.Sc. Criminology row
-- reading "Past the maximum period or not read · returning": "why is school fee setup for pg is not working, we have already define
-- their years and level, 800 A, B, Extention, 900 A, B. C Extention etc" — asked what a student past the maximum period pays, the
-- University chose the extension fee.
--
-- V651 reads a PG student's stage by the sessions the calendar counts from the start of the cycle (the admission session where none
-- is recorded): a Masters student admitted in 2022/2023 or earlier is past 800 C — Extension in 2025/2026, a PhD student admitted in
-- 2020/2021 or earlier past 900 E — Extension 2, a PG Diploma student admitted in 2023/2024 or earlier past 700 Extension. Such a
-- student had no stage, so no line naming a stage reached them, and the lines the Bursary uploaded on 27 October 2026 name a stage
-- (or Fresh) for every programme: on the copy of 22 October 2026 with those lines, 1,111 of the 3,453 PG students had no fee, 1,074
-- of them past the maximum period (Masters 673, PhD 387, PG Diploma 14). They could not pay or register; the only way on was a
-- restart, one student at a time (requested, recommended by the department, approved by the Dean).
--
-- V693: admissions.pg_fee_stages_of(session, students) — the stage a student is charged at: V651's reading, except that a student
-- past the maximum period whose cycle is still open (MAXIMUM_PERIOD_REACHED: an active cycle, or none recorded yet; not graduated,
-- not closed, no restart) is read at the last stage of their qualification (800 C — Extension, 900 E — Extension 2, 700 Extension),
-- with its fresh/returning category, beyond still true. Every fee reader takes it in place of admissions.pg_stages_of —
-- finance.charges_of_as, fee_stated, due_for_semester, session_fee_total, fee_profiles (the bulk sums and positions),
-- historical_rows_read, pg_unstated, pg_unstated_by_stage and the payment's PG context — so the student is charged, can pay and
-- register. The PG School's reading is unchanged (admissions.pg_stages_of: the stage lists, the counts, the data-quality list, the
-- student's page still say "Past the maximum period"); closing the cycle (exhausted, closed) or an approved restart ends it (a
-- restart begins at the first stage, fresh, as before). pg_unstated_by_stage names such a group "Past the maximum period — charged
-- as 800 C — Extension". Nothing about a student or a fee line is written.

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'pgschool', true),
       set_config('moaum.reason', 'V693: a postgraduate student past the maximum period charged the last stage''s fee line (the University, 29 October 2026)', true);

-- ── the stage a student is charged at ──
CREATE OR REPLACE FUNCTION admissions.pg_fee_stages_of(p_session text, p_students uuid[] DEFAULT NULL)
RETURNS TABLE(student_id uuid, cycle_id uuid, cycle_no integer, qualification text, programme_code text, start_session text,
              cycle_status text, stage_code text, stage_label text, stage_seq integer, stages integer, is_extension boolean,
              official boolean, category text, beyond boolean, recommendation text)
LANGUAGE plpgsql
STABLE
ROWS 1000
AS $$
BEGIN
    -- PL/pgSQL as admissions.pg_stages_of is: never folded into the caller's query
    RETURN QUERY
    WITH last AS MATERIALIZED (
        SELECT DISTINCT ON (st.qualification) st.qualification, st.code, st.label, st.sequence, st.extension_number IS NOT NULL AS ext
          FROM admissions.pg_stage st WHERE st.active
         ORDER BY st.qualification, st.sequence DESC)
    SELECT x.student_id, x.cycle_id, x.cycle_no, x.qualification, x.programme_code, x.start_session, x.cycle_status,
           CASE WHEN l.code IS NOT NULL THEN l.code ELSE x.stage_code END,
           CASE WHEN l.code IS NOT NULL THEN l.label ELSE x.stage_label END,
           x.stage_seq, x.stages,
           CASE WHEN l.code IS NOT NULL THEN l.ext ELSE x.is_extension END,
           x.official,
           CASE WHEN l.code IS NOT NULL THEN CASE WHEN l.sequence = 1 THEN 'FRESH' ELSE 'RETURNING' END ELSE x.category END,
           x.beyond, x.recommendation
      FROM admissions.pg_stages_of(p_session, p_students) x
      LEFT JOIN last l ON l.qualification = x.qualification AND x.stage_code IS NULL AND x.recommendation = 'MAXIMUM_PERIOD_REACHED';
END $$;
COMMENT ON FUNCTION admissions.pg_fee_stages_of(text, uuid[]) IS
  'V693: the stage a PG student is charged at in a session — admissions.pg_stages_of, except that a student past the maximum period whose cycle is still open (MAXIMUM_PERIOD_REACHED: an active cycle or none recorded; not graduated, not closed, no restart) is read at the last stage of the qualification (800 C — Extension, 900 E — Extension 2, 700 Extension) with its category, beyond still true. Every fee reader reads it; the PG School''s screens read admissions.pg_stages_of.';

-- ── every fee reader reads the stage a student is charged at (the bodies as they stand on main, admissions.pg_stages_of read as
--    admissions.pg_fee_stages_of; nothing else changed but where marked V693) ──

-- finance.charges_of_as: the student's own charges
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
                   AND NOT people.is_postgraduate(s.entry_mode, pp.category)) AS src,   -- V451: the faculty charged as, while a rule is in force
               pgs.stage_code AS pg_stage, pgs.category AS pg_category   -- V651: the student's PG stage and fresh/returning in the session
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
          LEFT JOIN LATERAL (SELECT x.stage_code, x.category FROM admissions.pg_fee_stages_of(p_session, ARRAY[s.id]) x) pgs ON true   -- V651
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
       AND finance.pg_stage_line(f.pg_stage, f.fee_category, me.pg_stage, me.pg_category)   -- V651: a line for a PG stage, or for fresh or returning PG students, reaches only them
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)))
       AND (f.semester IS NULL
            OR f.semester <= coalesce((SELECT max(sm.number) FROM policy.semester sm
                                        WHERE sm.session = p_session AND sm.state = 'OPEN'), 3))
     ORDER BY f.ord, f.item;
$function$;

-- finance.fee_stated: whether a line is stated for the student
CREATE OR REPLACE FUNCTION finance.fee_stated(p_student uuid, p_session text)
 RETURNS boolean
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
               (SELECT finance.fee_source_of(pp.faculty_code, p_session) FROM ref.programme pp
                 WHERE pp.code = s.programme_code AND s.entry_mode IS DISTINCT FROM 'CCE'
                   AND NOT people.is_postgraduate(s.entry_mode, pp.category)) AS src,   -- V451: the faculty charged as, while a rule is in force
               pgs.stage_code AS pg_stage, pgs.category AS pg_category   -- V651: the student's PG stage and fresh/returning in the session
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
          LEFT JOIN LATERAL (SELECT x.stage_code, x.category FROM admissions.pg_fee_stages_of(p_session, ARRAY[s.id]) x) pgs ON true   -- V651
         WHERE s.id = p_student)
    SELECT (p_session < coalesce(finance.schedule_from(), p_session) AND (SELECT me.entry_mode FROM me) IS DISTINCT FROM 'CCE')
        OR EXISTS (
        SELECT 1
          FROM finance.fee_schedule f
          CROSS JOIN me
          JOIN ref.programme p ON p.code = me.programme_code
          LEFT JOIN ref.fee_group g ON g.code = f.fee_group
          LEFT JOIN home ON true
         WHERE f.session = p_session AND f.ended_at IS NULL AND f.kind = 'FEE'
           AND f.spillover = me.is_spill
           AND (f.level IS NULL OR f.level = CASE WHEN me.is_spill THEN me.final_level ELSE me.current_level END)   -- V613: on a spillover line the level is the programme's final level
           AND (f.spill_year IS NULL OR f.spill_year = me.spill_year)   -- V613: SP1, SP2, SP3, or any spillover year
           AND ((f.entry_mode IS NULL AND me.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = me.entry_mode)   -- V379: a line naming no entry mode never reaches a CCE student
           AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code OR (f.faculty_code = me.src AND f.programme_code IS NULL))
           AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
           AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
           AND finance.pg_line(me.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, g.applies_category)   -- V391: a full-time line never reaches a postgraduate student
           AND finance.pg_stage_line(f.pg_stage, f.fee_category, me.pg_stage, me.pg_category)   -- V651: a line for a PG stage, or for fresh or returning PG students, reaches only them
           AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state))))
$function$;

-- finance.due_for_semester: a semester's fee
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
                   AND NOT people.is_postgraduate(s.entry_mode, pp.category)) AS src,   -- V451: the faculty charged as, while a rule is in force
               pgs.stage_code AS pg_stage, pgs.category AS pg_category   -- V651: the student's PG stage and fresh/returning in the session
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
          LEFT JOIN LATERAL (SELECT x.stage_code, x.category FROM admissions.pg_fee_stages_of(p_session, ARRAY[s.id]) x) pgs ON true   -- V651
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
       AND finance.pg_stage_line(f.pg_stage, f.fee_category, me.pg_stage, me.pg_category)   -- V651: a line for a PG stage, or for fresh or returning PG students, reaches only them
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)))
       AND (f.semester IS NULL OR f.semester <= p_semester);
$function$;

-- finance.session_fee_total: the session's fee
CREATE OR REPLACE FUNCTION finance.session_fee_total(p_student uuid, p_session text)
 RETURNS numeric
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS MATERIALIZED (   -- V451: read once, not once per fee line
        SELECT s.id, s.programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
               (SELECT finance.fee_source_of(pp.faculty_code, p_session) FROM ref.programme pp
                 WHERE pp.code = s.programme_code AND s.entry_mode IS DISTINCT FROM 'CCE'
                   AND NOT people.is_postgraduate(s.entry_mode, pp.category)) AS src,   -- V451: the faculty charged as, while a rule is in force
               pgs.stage_code AS pg_stage, pgs.category AS pg_category   -- V651: the student's PG stage and fresh/returning in the session
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
          LEFT JOIN LATERAL (SELECT x.stage_code, x.category FROM admissions.pg_fee_stages_of(p_session, ARRAY[s.id]) x) pgs ON true   -- V651
         WHERE s.id = p_student)
    SELECT coalesce(sum(f.amount), 0)
      FROM finance.fee_schedule f
      CROSS JOIN me
      JOIN ref.programme p ON p.code = me.programme_code
      LEFT JOIN ref.fee_group g ON g.code = f.fee_group
      CROSS JOIN home
     WHERE f.session = p_session AND f.ended_at IS NULL
       AND (f.level IS NULL OR f.level = me.current_level)
       AND ((f.entry_mode IS NULL AND me.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = me.entry_mode)   -- V379: a line naming no entry mode never reaches a CCE student
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code OR (f.faculty_code = me.src AND f.programme_code IS NULL))
       AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND finance.pg_line(me.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, g.applies_category)   -- V391: a full-time line never reaches a postgraduate student
       AND finance.pg_stage_line(f.pg_stage, f.fee_category, me.pg_stage, me.pg_category)   -- V651: a line for a PG stage, or for fresh or returning PG students, reaches only them
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)));
$function$;

-- finance.fee_profiles: the bulk fee profiles (fee_sums, fee_positions_of)
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
    regs AS MATERIALIZED (
        SELECT cr.student_id, array_agg(DISTINCT cr.semester ORDER BY cr.semester) AS sems
          FROM registration.course_registration cr
         WHERE cr.session = p_session AND EXISTS (SELECT 1 FROM registration.entry e WHERE e.registration_id = cr.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN'))
         GROUP BY cr.student_id),
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

-- finance.historical_rows_read: the historical assessment
CREATE OR REPLACE FUNCTION finance.historical_rows_read(p_students uuid[])
 RETURNS TABLE(student_id uuid, session text, semester integer, level integer, programme_code text, assessed numeric, source text, source_ref text, assessment_id uuid, structure_amount numeric, structure_lines integer, pending_id uuid, pending_ref text, pending_amount numeric, paid numeric, outstanding numeric, credit numeric, status text, waived numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS MATERIALIZED (SELECT lower(home_state) AS home_state FROM finance.fee_setting WHERE id = 1),
    bounds AS MATERIALIZED (SELECT finance.historical_start() AS start,
                                   (SELECT max(a.name) FROM policy.academic_session a
                                     WHERE a.state NOT IN ('CANCELLED', 'DRAFT') AND a.name < coalesce(policy.university_current_session(), '9999/9999')) AS before_current),
    -- the calendar's order, as people.level_in counts the sessions since admission (every session row, by its start)
    cal AS MATERIALIZED (SELECT a.name, a.state, a.semesters, row_number() OVER (ORDER BY a.starts_on, a.name) AS idx FROM policy.academic_session a),
    st AS MATERIALIZED (
        SELECT s.id, s.programme_code, p.faculty_code, p.category, s.entry_mode, s.entry_session, s.entry_level, s.current_level,
               people.is_postgraduate(s.entry_mode, p.category) AS pg,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) = (SELECT h.home_state FROM home h) AS indigene,
               greatest(s.entry_session, b.start) AS first_session,
               CASE WHEN s.status = 'GRADUATED' OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED')
                    THEN records.graduation_session(s.id) ELSE b.before_current END AS last_session
          FROM unnest(p_students) u(id)
          JOIN people.student s ON s.id = u.id
          JOIN ref.programme p ON p.code = s.programme_code
          CROSS JOIN bounds b
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
         WHERE s.entry_session IS NOT NULL),
    -- the programme's final level read once a programme
    fl AS MATERIALIZED (SELECT d.programme_code, finance.final_level(d.programme_code) AS final_level FROM (SELECT DISTINCT st.programme_code FROM st) d),
    per0 AS MATERIALIZED (
        -- the sessions of the record, each semester of each, a deferred session or semester left out
        SELECT st.*, fl.final_level, a.name AS session, sm.n AS semester, a.idx AS ses_idx
          FROM st
          JOIN fl ON fl.programme_code = st.programme_code
          JOIN cal a ON a.name >= st.first_session AND a.name <= st.last_session AND a.state NOT IN ('CANCELLED', 'DRAFT')
          CROSS JOIN LATERAL generate_series(1, a.semesters) sm(n)
         WHERE st.last_session IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM people.deferment d
                            WHERE d.student_id = st.id AND d.session = a.name AND d.state IN ('APPROVED', 'ACTIVE', 'COMPLETED')
                              AND (d.kind = 'SESSION' OR d.semester = sm.n))),
    -- the level of each period, read as people.level_in reads it — the semester's registration, else the session's, else the
    -- enrolment, else counted from admission (a postgraduate's own level) — for every student at once
    reg AS MATERIALIZED (SELECT r.student_id, r.session, r.semester, r.level, r.status IN ('APPROVED', 'LOCKED') AS ok
                           FROM registration.course_registration r WHERE r.student_id = ANY (p_students)),
    reg_sem AS (SELECT DISTINCT ON (g.student_id, g.session, g.semester) g.student_id, g.session, g.semester, g.level FROM reg g
                 ORDER BY g.student_id, g.session, g.semester, g.ok DESC),
    reg_ses AS (SELECT DISTINCT ON (g.student_id, g.session) g.student_id, g.session, g.level FROM reg g ORDER BY g.student_id, g.session, g.ok DESC, g.semester),
    enr AS (SELECT DISTINCT ON (e.student_id, e.session) e.student_id, e.session, e.level FROM people.enrolment e WHERE e.student_id = ANY (p_students)
             ORDER BY e.student_id, e.session),
    per AS MATERIALIZED (
        SELECT p0.*, coalesce(rs.level, rx.level, en.level,
                              CASE WHEN p0.pg THEN p0.current_level
                                   WHEN es.idx IS NOT NULL AND p0.ses_idx >= es.idx THEN least(600, p0.entry_level + 100 * (p0.ses_idx - es.idx)::int) END,
                              p0.current_level) AS level
          FROM per0 p0
          LEFT JOIN cal es ON es.name = p0.entry_session
          LEFT JOIN reg_sem rs ON rs.student_id = p0.id AND rs.session = p0.session AND rs.semester = p0.semester
          LEFT JOIN reg_ses rx ON rx.student_id = p0.id AND rx.session = p0.session
          LEFT JOIN enr en ON en.student_id = p0.id AND en.session = p0.session),
    ses AS MATERIALIZED (
        -- one profile a session: the student as they were in its first semester on the record
        SELECT DISTINCT ON (pe.id, pe.session) pe.* FROM per pe ORDER BY pe.id, pe.session, pe.semester),
    -- the faculty a faculty is charged as, read once a faculty and session; a PG student's stage read once a session
    src AS MATERIALIZED (SELECT d.faculty_code, d.session, finance.fee_source_of(d.faculty_code, d.session) AS src
                           FROM (SELECT DISTINCT x.faculty_code, x.session FROM ses x WHERE x.entry_mode IS DISTINCT FROM 'CCE' AND NOT x.pg) d),
    pgs AS MATERIALIZED (SELECT y.student_id, d.session, y.stage_code, y.category
                           FROM (SELECT x.session, array_agg(x.id) AS ids FROM ses x WHERE x.pg GROUP BY x.session) d
                           CROSS JOIN LATERAL admissions.pg_fee_stages_of(d.session, d.ids) y),
    prof AS MATERIALIZED (
        -- the student as they were in the session: spillover read from its level against the programme's final level
        SELECT pe.*, coalesce(pe.level > pe.final_level, false) AS is_spill,
               CASE WHEN pe.level > pe.final_level THEN least((pe.level - pe.final_level) / 100, 3) END AS spill_year,
               CASE WHEN pe.level > pe.final_level THEN finance.reg_semesters(pe.id, pe.session) END AS reg_sems,   -- V616: read for a spillover student only
               sr.src, pg.stage_code AS pg_stage, pg.category AS pg_category
          FROM ses pe
          LEFT JOIN src sr ON sr.faculty_code = pe.faculty_code AND sr.session = pe.session AND pe.entry_mode IS DISTINCT FROM 'CCE' AND NOT pe.pg
          LEFT JOIN pgs pg ON pg.student_id = pe.id AND pg.session = pe.session),
    matched AS (
        -- the session's fee lines that reach the student as they were; a whole-session line is due with the first semester
        SELECT pr.id AS student_id, pr.session, coalesce(f.semester, 1) AS semester, f.amount
          FROM prof pr
          JOIN finance.fee_schedule f ON f.session = pr.session AND f.ended_at IS NULL AND f.kind = 'FEE'
          LEFT JOIN ref.fee_group g ON g.code = f.fee_group
         WHERE f.spillover = pr.is_spill
           AND (f.level IS NULL OR f.level = CASE WHEN pr.is_spill THEN pr.final_level ELSE pr.level END)
           AND (f.spill_year IS NULL OR f.spill_year = pr.spill_year)
           AND finance.spill_line_applies(pr.is_spill, f.semester, pr.reg_sems)
           AND ((f.entry_mode IS NULL AND pr.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = pr.entry_mode)
           AND (f.faculty_code IS NULL OR f.faculty_code = pr.faculty_code OR (f.faculty_code = pr.src AND f.programme_code IS NULL))
           AND (f.programme_code IS NULL OR f.programme_code = pr.programme_code)
           AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = pr.category)
           AND finance.pg_line(pr.entry_mode = 'POSTGRADUATE' OR pr.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, g.applies_category)
           AND finance.pg_stage_line(f.pg_stage, f.fee_category, pr.pg_stage, pr.pg_category)
           AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = pr.indigene)),
    struct AS (SELECT m.student_id, m.session, m.semester, sum(m.amount) AS amount, count(*)::int AS lines FROM matched m GROUP BY 1, 2, 3),
    stated AS (SELECT DISTINCT m.student_id, m.session FROM matched m),
    apr AS (SELECT a.id, a.reference, a.student_id, a.session, a.semester, a.amount FROM finance.historical_assessment a
             WHERE a.student_id = ANY (p_students) AND a.state = 'APPROVED'),
    pend AS (SELECT a.id, a.reference, a.student_id, a.session, a.semester, a.amount FROM finance.historical_assessment a
              WHERE a.student_id = ANY (p_students) AND a.state IN ('PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION', 'DRAFT')),
    -- V665: the approved waivers and adjustments of each period
    wv AS (SELECT w.student_id, w.session, w.semester, sum(w.amount) AS waived FROM finance.historical_waiver w
            WHERE w.student_id = ANY (p_students) AND w.state = 'APPROVED' GROUP BY 1, 2, 3),
    pay AS (SELECT r.student_id, r.session, sum(r.amount) AS paid FROM finance.payment_reference r
             WHERE r.student_id = ANY (p_students) AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
             GROUP BY 1, 2),
    base0 AS (
        SELECT pr.id AS student_id, pr.session, pr.semester, pr.level, pr.programme_code,
               coalesce(ap.amount, CASE WHEN sd.session IS NOT NULL THEN coalesce(sr.amount, 0) END) AS assessed,
               CASE WHEN ap.id IS NOT NULL THEN 'ASSESSMENT' WHEN sd.session IS NOT NULL THEN 'STRUCTURE' ELSE 'NONE' END AS source,
               CASE WHEN ap.id IS NOT NULL THEN ap.reference
                    WHEN sd.session IS NOT NULL THEN pr.session || ' fee structure' || CASE WHEN sr.lines IS NULL THEN ' (nothing due this semester)'
                                                                                          ELSE ' (' || sr.lines || CASE WHEN sr.lines = 1 THEN ' line)' ELSE ' lines)' END END END AS source_ref,
               ap.id AS assessment_id, sr.amount AS structure_amount, coalesce(sr.lines, 0) AS structure_lines,
               pn.id AS pending_id, pn.reference AS pending_ref, pn.amount AS pending_amount,
               coalesce(py.paid, 0) AS session_paid, coalesce(w.waived, 0) AS waived
          FROM per pr
          LEFT JOIN struct sr ON sr.student_id = pr.id AND sr.session = pr.session AND sr.semester = pr.semester
          LEFT JOIN stated sd ON sd.student_id = pr.id AND sd.session = pr.session
          LEFT JOIN apr ap ON ap.student_id = pr.id AND ap.session = pr.session AND ap.semester = pr.semester
          LEFT JOIN pend pn ON pn.student_id = pr.id AND pn.session = pr.session AND pn.semester = pr.semester
          LEFT JOIN pay py ON py.student_id = pr.id AND py.session = pr.session
          LEFT JOIN wv w ON w.student_id = pr.id AND w.session = pr.session AND w.semester = pr.semester),
    -- what the period is owed on: the amount assessed less the approved waivers (never below nothing)
    base AS (SELECT b0.*, CASE WHEN b0.assessed IS NULL THEN NULL ELSE greatest(b0.assessed - b0.waived, 0) END AS net FROM base0 b0),
    alloc AS (
        -- the session's payments fill the assessed semesters in order (each on what it is owed on); what is left goes to the first
        -- semester not yet assessed, else stands as a credit on the session's last semester
        SELECT b.*,
               coalesce(sum(b.net) OVER (PARTITION BY b.student_id, b.session ORDER BY b.semester ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS before_me,
               coalesce(sum(b.net) OVER (PARTITION BY b.student_id, b.session), 0) AS session_assessed,
               min(b.semester) FILTER (WHERE b.assessed IS NULL) OVER (PARTITION BY b.student_id, b.session) AS first_unassessed,
               max(b.semester) OVER (PARTITION BY b.student_id, b.session) AS last_semester
          FROM base b),
    fin AS (
        SELECT a.*,
               CASE WHEN a.net IS NOT NULL THEN least(greatest(a.session_paid - a.before_me, 0), a.net)
                    WHEN a.semester = a.first_unassessed THEN greatest(a.session_paid - a.session_assessed, 0)
                    ELSE 0 END AS paid_here,
               CASE WHEN a.first_unassessed IS NULL AND a.semester = a.last_semester THEN greatest(a.session_paid - a.session_assessed, 0) ELSE 0 END AS credit_here
          FROM alloc a)
    SELECT f.student_id, f.session, f.semester, f.level, f.programme_code, f.assessed, f.source, f.source_ref, f.assessment_id,
           f.structure_amount, f.structure_lines, f.pending_id, f.pending_ref, f.pending_amount,
           f.paid_here + f.credit_here AS paid,
           CASE WHEN f.net IS NULL THEN NULL ELSE finance.fee_owed(f.net, f.paid_here) END AS outstanding,
           f.credit_here AS credit,
           CASE WHEN f.net IS NULL THEN CASE WHEN f.pending_id IS NOT NULL THEN 'PENDING_APPROVAL' ELSE 'REQUIRES_REVIEW' END
                WHEN f.credit_here >= 1 THEN 'CREDIT'
                WHEN finance.fee_owed(f.net, f.paid_here) = 0 THEN 'CLEARED'
                WHEN f.paid_here > 0 THEN 'PARTIALLY_PAID'
                ELSE 'OUTSTANDING' END AS status,
           f.waived
      FROM fin f
$function$;

-- finance.pg_unstated: the PG students with no fee stated
CREATE OR REPLACE FUNCTION finance.pg_unstated(p_session text)
 RETURNS TABLE(level integer, programme_code text, programme text, students bigint)
 LANGUAGE sql
 STABLE
AS $function$
    -- the stage and category tell students apart only when the session states a line by them (else the groups stay as V447's)
    WITH staged AS MATERIALIZED (SELECT EXISTS (SELECT 1 FROM finance.fee_schedule f WHERE f.session = p_session AND f.ended_at IS NULL
                                                AND (f.pg_stage IS NOT NULL OR f.fee_category IS NOT NULL)) AS y),
    pgs AS MATERIALIZED (SELECT x.student_id, x.stage_code, x.category FROM admissions.pg_fee_stages_of(p_session, NULL) x, staged WHERE staged.y),
    live AS (
        -- the live PG students, with the facts finance.fee_stated reads of a student (the state of origin as it reads it, V651 the stage)
        SELECT s.id, s.current_level, s.programme_code, p.name, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) = lower(h.home_state) AS indigene,
               pgs.stage_code, pgs.category
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
          LEFT JOIN finance.fee_setting h ON h.id = 1
          LEFT JOIN pgs ON pgs.student_id = s.id
         WHERE people.is_postgraduate(s.entry_mode, p.category)
           AND s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')),
    alike AS (
        -- one student of each group of alike students, asked the real question
        SELECT g.programme_code, g.current_level, g.entry_mode, g.indigene, g.stage_code, g.category, finance.fee_stated(g.one, p_session) AS stated
          FROM (SELECT l.programme_code, l.current_level, l.entry_mode, l.indigene, l.stage_code, l.category, (array_agg(l.id))[1] AS one
                  FROM live l
                 GROUP BY l.programme_code, l.current_level, l.entry_mode, l.indigene, l.stage_code, l.category) g)
    SELECT l.current_level, l.programme_code, l.name, count(*)
      FROM live l
      JOIN alike a ON a.programme_code = l.programme_code
                  AND a.current_level IS NOT DISTINCT FROM l.current_level
                  AND a.entry_mode IS NOT DISTINCT FROM l.entry_mode
                  AND a.indigene IS NOT DISTINCT FROM l.indigene
                  AND a.stage_code IS NOT DISTINCT FROM l.stage_code
                  AND a.category IS NOT DISTINCT FROM l.category
     WHERE NOT a.stated
     GROUP BY l.current_level, l.programme_code, l.name
     ORDER BY l.current_level, l.programme_code;
$function$;

-- finance.pg_unstated_by_stage: the same, by stage
CREATE OR REPLACE FUNCTION finance.pg_unstated_by_stage(p_session text)
 RETURNS TABLE(level integer, programme_code text, programme text, stage_code text, stage_label text, category text, students bigint)
 LANGUAGE sql
 STABLE
AS $function$
    -- as finance.pg_unstated (V447, V651), each student's stage read for the list; alike students are told apart by the stage and
    -- category only when the session states a line by them (else one student of a group answers for it, as before)
    WITH staged AS MATERIALIZED (SELECT EXISTS (SELECT 1 FROM finance.fee_schedule f WHERE f.session = p_session AND f.ended_at IS NULL
                                                AND (f.pg_stage IS NOT NULL OR f.fee_category IS NOT NULL)) AS y),
    pgs AS MATERIALIZED (SELECT x.student_id, x.stage_code, x.category, x.beyond FROM admissions.pg_fee_stages_of(p_session, NULL) x),
    live AS (
        SELECT s.id, s.current_level, s.programme_code, p.name, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) = lower(h.home_state) AS indigene,
               pgs.stage_code, pgs.category, coalesce(pgs.beyond, false) AS beyond,   -- V693
               CASE WHEN staged.y THEN pgs.stage_code END AS stage_key, CASE WHEN staged.y THEN pgs.category END AS category_key
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code
          CROSS JOIN staged
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
          LEFT JOIN finance.fee_setting h ON h.id = 1
          LEFT JOIN pgs ON pgs.student_id = s.id
         WHERE people.is_postgraduate(s.entry_mode, p.category)
           AND s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')),
    alike AS (
        SELECT g.programme_code, g.current_level, g.entry_mode, g.indigene, g.stage_key, g.category_key, finance.fee_stated(g.one, p_session) AS stated
          FROM (SELECT l.programme_code, l.current_level, l.entry_mode, l.indigene, l.stage_key, l.category_key, (array_agg(l.id))[1] AS one
                  FROM live l
                 GROUP BY l.programme_code, l.current_level, l.entry_mode, l.indigene, l.stage_key, l.category_key) g)
    SELECT l.current_level, l.programme_code, l.name, l.stage_code,
           CASE WHEN l.beyond AND st.label IS NOT NULL THEN 'Past the maximum period — charged as ' || st.label ELSE st.label END,   -- V693
           l.category, count(*)
      FROM live l
      JOIN alike a ON a.programme_code = l.programme_code
                  AND a.current_level IS NOT DISTINCT FROM l.current_level
                  AND a.entry_mode IS NOT DISTINCT FROM l.entry_mode
                  AND a.indigene IS NOT DISTINCT FROM l.indigene
                  AND a.stage_key IS NOT DISTINCT FROM l.stage_key
                  AND a.category_key IS NOT DISTINCT FROM l.category_key
      LEFT JOIN admissions.pg_stage st ON st.code = l.stage_code
     WHERE NOT a.stated
     GROUP BY l.current_level, l.programme_code, l.name, l.stage_code, st.label, st.sequence, l.category, l.beyond
     ORDER BY l.current_level, l.programme_code, st.sequence NULLS LAST, l.beyond;
$function$;

-- finance.trg_payment_pg_context: the stage a school-fees reference is raised under
CREATE OR REPLACE FUNCTION finance.trg_payment_pg_context()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO finance.payment_pg_context (reference_id, student_id, session, cycle_id, cycle_no, qualification, stage_code, category, official)
    SELECT NEW.id, NEW.student_id, NEW.session, x.cycle_id, x.cycle_no, x.qualification, x.stage_code, x.category, x.official
      FROM admissions.pg_fee_stages_of(NEW.session, ARRAY[NEW.student_id]) x
    ON CONFLICT (reference_id) DO NOTHING;
    RETURN NULL;
END $function$;

COMMENT ON FUNCTION finance.pg_unstated_by_stage(text) IS
  'V653: the live PG students with no fee line stated for the session, by programme, level, PG stage and fresh/returning — the stage the Bursary states next. V693: the stage a student is charged at (admissions.pg_fee_stages_of); a student past the maximum period is in a group of their own, "Past the maximum period — charged as 800 C — Extension". finance.pg_unstated is the same count without the stage.';

COMMIT;
