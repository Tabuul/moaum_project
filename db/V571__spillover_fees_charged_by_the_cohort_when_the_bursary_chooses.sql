-- V571: the spillover fee lines charged to the students the cohort engine reads as spillover, when the Bursary chooses it.
--
-- V088 charges a student the spillover lines when the record's level is above the programme's final level (a four-year
-- programme's student at 500). The cohort engine (V331, V475, V558) reads spillover by the sessions past the programme's length
-- and puts the record AT the final level: on the live-shaped copy of 19 October 2026 the fee rule finds 252 spillover students,
-- the engine about 13,000 (SP1 2,039, SP2 5,543, the limit 5,489). Once the levels are corrected those students are charged as
-- final-year students, never the 84 spillover lines.
--
--   * finance.fee_setting.spillover_basis: LEVEL (V088's rule, kept by default) or COHORT (the engine's spillover — SP1, SP2 …
--     and the limit reached). The Bursary sets it with a reason; finance.set_spill_basis keeps who, when and why.
--   * finance.spill(student, level, programme, status): the one test, read by the six functions that held V088's test inline —
--     fee_profiles (and so session_charges and fee_sums), charges_of_as, due_for_semester, fee_stated, fee_gaps and is_spillover —
--     each restated from its current text with only that test changed. moaum.spill_basis, set for a transaction, reads the other
--     basis without changing the setting: the preview of who would move and what they would owe.
--   * finance.spill_basis_moves(): the current students whose spillover differs between the two bases.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'bursar', true);
SELECT set_config('moaum.reason', 'V571: the spillover fee basis', true);

ALTER TABLE finance.fee_setting
    ADD COLUMN spillover_basis        text NOT NULL DEFAULT 'LEVEL',
    ADD COLUMN spillover_basis_set_at timestamptz,
    ADD COLUMN spillover_basis_set_by uuid,
    ADD COLUMN spillover_basis_reason text,
    ADD CONSTRAINT ck_fee_setting_spillover_basis CHECK (spillover_basis IN ('LEVEL', 'COHORT'));
COMMENT ON COLUMN finance.fee_setting.spillover_basis IS
  'V571: who is charged the spillover fee lines — LEVEL, a level above the programme''s final level (V088), or COHORT, the cohort engine''s spillover (SP1, SP2 … and the limit reached)';

-- the basis in force: a transaction may read the other one (moaum.spill_basis) for a preview; the setting otherwise
CREATE FUNCTION finance.spill_basis()
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(CASE WHEN current_setting('moaum.spill_basis', true) IN ('LEVEL', 'COHORT') THEN current_setting('moaum.spill_basis', true) END,
                    (SELECT g.spillover_basis FROM finance.fee_setting g WHERE g.id = 1), 'LEVEL')
$fn$;

-- the one test of a spillover student for the fee lines
CREATE FUNCTION finance.spill(p_student uuid, p_level integer, p_programme text, p_status text)
RETURNS boolean LANGUAGE sql STABLE AS $fn$
    SELECT CASE WHEN coalesce(p_status, '') = 'GRADUATED' THEN false
                WHEN finance.spill_basis() = 'COHORT'
                    THEN coalesce((SELECT ap.spillover_state LIKE 'SPILLOVER%' FROM people.academic_position ap WHERE ap.student_id = p_student), false)
                ELSE coalesce(p_level > finance.final_level(p_programme), false) END
$fn$;
COMMENT ON FUNCTION finance.spill(uuid, integer, text, text) IS
  'V571: whether a student is charged the spillover fee lines, by the Bursary''s basis (finance.spill_basis)';

-- the current students whose spillover differs between the two bases (who would move if the basis changed)
CREATE FUNCTION finance.spill_basis_moves()
RETURNS TABLE (student_id uuid, by_level boolean, by_cohort boolean)
LANGUAGE sql STABLE AS $fn$
    WITH fl AS MATERIALIZED (SELECT pr.code, finance.final_level(pr.code) AS final FROM ref.programme pr)
    SELECT s.id, coalesce(s.current_level > fl.final, false), coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
      FROM people.student s
      JOIN fl ON fl.code = s.programme_code
      LEFT JOIN people.academic_position ap ON ap.student_id = s.id
     WHERE s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
       AND coalesce(s.current_level > fl.final, false) IS DISTINCT FROM coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
$fn$;
COMMENT ON FUNCTION finance.spill_basis_moves() IS
  'V571: the current students charged the spillover lines under one basis and not the other';

-- the Bursary's choice, with its reason, kept
CREATE FUNCTION finance.set_spill_basis(p_basis text, p_reason text)
RETURNS text LANGUAGE plpgsql AS $fn$
BEGIN
    IF upper(coalesce(p_basis, '')) NOT IN ('LEVEL', 'COHORT') THEN
        RAISE EXCEPTION 'FEE_SPILL_BASIS: the spillover lines are charged by the level (above the final level) or by the cohort (SP years)' USING ERRCODE = '23514';
    END IF;
    IF length(btrim(coalesce(p_reason, ''))) < 10 THEN
        RAISE EXCEPTION 'FEE_SPILL_REASON: say why the basis changes, in 10 characters or more' USING ERRCODE = '23514';
    END IF;
    UPDATE finance.fee_setting SET spillover_basis = upper(p_basis), spillover_basis_set_at = now(),
           spillover_basis_set_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, spillover_basis_reason = btrim(p_reason)
     WHERE id = 1;
    RETURN upper(p_basis);
END $fn$;

-- ── the six functions, restated from their current text with V088's test replaced by finance.spill ──────────────────────────
CREATE OR REPLACE FUNCTION finance.fee_profiles()
 RETURNS TABLE(student_id uuid, status text, programme_code text, faculty_code text, category text, current_level integer, entry_mode text, state text, is_spill boolean, profile_key text)
 LANGUAGE sql
 STABLE
AS $function$
    -- V537: each programme's final level read once (456 calls), not twice for every student: on a connection the portal has
    -- used a while, PostgreSQL 18 reads finance.final_level by a cached generic plan that costs about seven times as much a call
    WITH fl AS MATERIALIZED (SELECT pr.code, finance.final_level(pr.code) AS final FROM ref.programme pr),
    -- V571: the Bursary's basis for the spillover lines, read once (LEVEL: above the final level; COHORT: the cohort engine's spillover)
    basis AS MATERIALIZED (SELECT finance.spill_basis() AS b)
    SELECT s.id, s.status, s.programme_code, p.faculty_code, p.category, s.current_level, s.entry_mode,
           lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
           (s.status <> 'GRADUATED' AND CASE WHEN basis.b = 'COHORT' THEN coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
                                                ELSE coalesce(s.current_level > fl.final, false) END) AS is_spill,
           concat_ws('|', s.programme_code, s.current_level, s.entry_mode,
                     lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))),
                     (s.status <> 'GRADUATED' AND CASE WHEN basis.b = 'COHORT' THEN coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
                                                ELSE coalesce(s.current_level > fl.final, false) END)) AS profile_key
      FROM people.student s
      JOIN ref.programme p ON p.code = s.programme_code
      JOIN fl ON fl.code = s.programme_code
      CROSS JOIN basis
      LEFT JOIN people.academic_position ap ON ap.student_id = s.id
      LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
      LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
$function$;

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
    basis AS MATERIALIZED (SELECT finance.spill_basis() AS b),   -- V571
    live AS (
        SELECT s.programme_code, p.faculty_code, p.category, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) = (SELECT h.home_state FROM home h) AS indigene,
               CASE WHEN basis.b = 'COHORT' THEN coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
                    ELSE coalesce(s.current_level > fl.final, false) END AS is_spill
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

CREATE OR REPLACE FUNCTION finance.charges_of_as(p_student uuid, p_session text, p_kinds text[], p_programme text)
 RETURNS TABLE(id uuid, item text, amount numeric, ord integer)
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS MATERIALIZED (   -- V451: read once, not once per fee line
        SELECT s.id, coalesce(p_programme, s.programme_code) AS programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
               finance.spill(s.id, s.current_level, coalesce(p_programme, s.programme_code), s.status) AS is_spill,
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
       AND (me.is_spill OR f.level IS NULL OR f.level = me.current_level)
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
       AND (me.is_spill OR f.level IS NULL OR f.level = me.current_level)
       AND ((f.entry_mode IS NULL AND me.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = me.entry_mode)   -- V379: a line naming no entry mode never reaches a CCE student
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code OR (f.faculty_code = me.src AND f.programme_code IS NULL))
       AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND finance.pg_line(me.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, g.applies_category)   -- V391: a full-time line never reaches a postgraduate student
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)))
       AND (f.semester IS NULL OR f.semester <= p_semester);
$function$;

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
               (SELECT finance.fee_source_of(pp.faculty_code, p_session) FROM ref.programme pp
                 WHERE pp.code = s.programme_code AND s.entry_mode IS DISTINCT FROM 'CCE'
                   AND NOT people.is_postgraduate(s.entry_mode, pp.category)) AS src   -- V451: the faculty charged as, while a rule is in force
          FROM people.student s
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
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
           AND (me.is_spill OR f.level IS NULL OR f.level = me.current_level)
           AND ((f.entry_mode IS NULL AND me.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = me.entry_mode)   -- V379: a line naming no entry mode never reaches a CCE student
           AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code OR (f.faculty_code = me.src AND f.programme_code IS NULL))
           AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
           AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
           AND finance.pg_line(me.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, g.applies_category)   -- V391: a full-time line never reaches a postgraduate student
           AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state))))
$function$;

CREATE OR REPLACE FUNCTION finance.is_spillover(p_student uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    SELECT finance.spill(s.id, s.current_level, s.programme_code, s.status)
      FROM people.student s WHERE s.id = p_student;
$function$;

COMMIT;
