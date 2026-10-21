-- ═══════════════════════════════════════
-- V613 — school-fee lines by spillover year: "400 Level (SP1) First semester", "400 Level (SP2) …", "500 Level (SP1) …"
--
--   A spillover fee line said only "Spillover": it reached every student in spillover, whatever their programme's final level and
--   whatever their spillover year (V088, V571). The Bursary wants to state the fee per level, spillover year and semester — the
--   list the University gave on 21 October 2026: 400 Level (SP1) first semester, 400 Level (SP1) second semester, 400 Level (SP2)
--   first and second, 500 Level (SP1) …, and so on. So:
--   - finance.fee_schedule.spill_year (1, 2 or 3; NULL = any spillover year, as every line stated so far) beside the level and the
--     semester; on a spillover line the level now names the programme's final level — 400 for a four-year programme, 500 for a
--     five-year one — and NULL still reaches every programme. No line stated before V613 carries a level on a spillover line.
--   - finance.spill_year(student, level, programme, status): the student's spillover year on the Bursary's basis (V571) — by the
--     cohort engine's count (SP1, SP2, the limit read as 3) or, by the level, the levels above the programme's final one — NULL
--     when not in spillover; finance.spill_year_of(spillover_cell, spill_year_cell) reads "SP1", "SP2", "SP3" from a sheet.
--   - every matcher reads it: charges_of_as (what a student owes), fee_stated, due_for_semester, fee_sums with fee_profiles (the
--     spillover year is part of a fee profile), fee_gaps (a group of spillover students is one per year, and the report names the
--     year and the final level) and watch_fee_gaps; fee_line_same_scope keeps SP1 and SP2 apart; the sheet (add_fee_lines, the
--     Spillover cell "SP1" or a spillYear column), the structure upload, the copies between sessions, faculties and programmes
--     and the upload preview carry the year.
--   Every function is restated from its current definition with the year added and nothing else changed.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V613: school-fee lines by spillover year', true);

ALTER TABLE finance.fee_schedule ADD COLUMN spill_year integer;
ALTER TABLE finance.fee_schedule ADD CONSTRAINT ck_fee_spill_year CHECK (spill_year IS NULL OR (spillover AND spill_year BETWEEN 1 AND 3));
COMMENT ON COLUMN finance.fee_schedule.spill_year IS
    'V613: the spillover year a spillover line is for — 1 (SP1), 2 (SP2) or 3 (SP3 and beyond); NULL = any spillover year. On a spillover line the level is the programme''s final level (400 on a four-year programme), NULL for every programme';
COMMENT ON COLUMN finance.fee_schedule.level IS
    'the level the line is for (100–900), NULL for every level; on a spillover line (V613) the programme''s final level — the level a spillover student stands at — NULL for every programme';

-- "SP1", "SP 2", "spillover 3" in a sheet's Spillover cell, or 1–3 (or SP1–SP3) in a spillYear column
CREATE OR REPLACE FUNCTION finance.spill_year_of(p_spillover text, p_spill_year text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT coalesce(
        CASE WHEN coalesce(p_spill_year, '') ~* '^\s*(sp\s*)?[1-3]\s*$' THEN (regexp_match(p_spill_year, '([1-3])'))[1]::int END,
        CASE WHEN coalesce(p_spillover, '') ~* '^\s*(sp|spill\s*-?\s*over)\s*[-_: ]?\s*(year\s*)?[1-3]\s*$' THEN (regexp_match(p_spillover, '([1-3])\s*$'))[1]::int END)
$function$;
COMMENT ON FUNCTION finance.spill_year_of(text, text) IS 'V613: the spillover year a sheet states — "SP1", "SP2", "SP3" in the Spillover cell, or 1–3 in a spillYear column; NULL when the cell says only Yes or nothing';

-- the student's spillover year on the Bursary's basis (V571): the cohort engine's count, or the levels above the programme's final one
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
                ELSE NULL END
$function$;
COMMENT ON FUNCTION finance.spill_year(uuid, integer, text, text) IS 'V613: the spillover year a student is in (1, 2, or 3 for the third and beyond) on the basis the Bursary set (V571: the cohort engine''s count, or the level above the programme''s final one); NULL when not in spillover — the twin of finance.spill';

-- the scope of a line: SP1 and SP2 are different scopes
CREATE OR REPLACE FUNCTION finance.fee_line_same_scope(x finance.fee_schedule, s finance.fee_schedule)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT lower(btrim(x.item)) = lower(btrim(s.item)) AND x.kind = s.kind
       AND x.level IS NOT DISTINCT FROM s.level AND x.entry_mode IS NOT DISTINCT FROM s.entry_mode
       AND x.faculty_code IS NOT DISTINCT FROM s.faculty_code AND x.programme_code IS NOT DISTINCT FROM s.programme_code
       AND x.fee_group IS NOT DISTINCT FROM s.fee_group AND x.semester IS NOT DISTINCT FROM s.semester
       AND x.indigene IS NOT DISTINCT FROM s.indigene AND x.spillover = s.spillover
       AND x.spill_year IS NOT DISTINCT FROM s.spill_year   -- V613
$function$;

-- the profiles (the return type changes: dropped and made again; its readers name it by its one signature)
DROP FUNCTION finance.fee_profiles();
CREATE OR REPLACE FUNCTION finance.fee_profiles()
 RETURNS TABLE(student_id uuid, status text, programme_code text, faculty_code text, category text, current_level integer, entry_mode text, state text, is_spill boolean, spill_year integer, final_level integer, profile_key text)
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
           CASE WHEN s.status = 'GRADUATED' THEN NULL
                WHEN basis.b = 'COHORT' THEN CASE WHEN ap.spillover_state LIKE 'SPILLOVER%' THEN least(greatest(coalesce(ap.spillover_years, 1), 1), 3) END
                WHEN s.current_level > fl.final THEN least((s.current_level - fl.final) / 100, 3) END AS spill_year,   -- V613
           fl.final AS final_level,   -- V613
           concat_ws('|', s.programme_code, s.current_level, s.entry_mode,
                     lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))),
                     (s.status <> 'GRADUATED' AND CASE WHEN basis.b = 'COHORT' THEN coalesce(ap.spillover_state LIKE 'SPILLOVER%', false)
                                                ELSE coalesce(s.current_level > fl.final, false) END),
                     CASE WHEN s.status = 'GRADUATED' THEN NULL
                          WHEN basis.b = 'COHORT' THEN CASE WHEN ap.spillover_state LIKE 'SPILLOVER%' THEN least(greatest(coalesce(ap.spillover_years, 1), 1), 3) END
                          WHEN s.current_level > fl.final THEN least((s.current_level - fl.final) / 100, 3) END) AS profile_key   -- V613: the spillover year is part of the profile
      FROM people.student s
      JOIN ref.programme p ON p.code = s.programme_code
      JOIN fl ON fl.code = s.programme_code
      CROSS JOIN basis
      LEFT JOIN people.academic_position ap ON ap.student_id = s.id
      LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
      LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
$function$;

-- the matchers
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
               finance.spill_year(s.id, s.current_level, coalesce(p_programme, s.programme_code), s.status) AS spill_year,   -- V613: SP1, SP2, SP3 (NULL when not in spillover)
               finance.final_level(coalesce(p_programme, s.programme_code)) AS final_level,   -- V613: the level a spillover line names
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
           AND (f.level IS NULL OR f.level = CASE WHEN me.is_spill THEN me.final_level ELSE me.current_level END)   -- V613: on a spillover line the level is the programme's final level
           AND (f.spill_year IS NULL OR f.spill_year = me.spill_year)   -- V613: SP1, SP2, SP3, or any spillover year
           AND ((f.entry_mode IS NULL AND me.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = me.entry_mode)   -- V379: a line naming no entry mode never reaches a CCE student
           AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code OR (f.faculty_code = me.src AND f.programme_code IS NULL))
           AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
           AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
           AND finance.pg_line(me.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, g.applies_category)   -- V391: a full-time line never reaches a postgraduate student
           AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state))))
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
       AND ((f.entry_mode IS NULL AND me.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = me.entry_mode)   -- V379: a line naming no entry mode never reaches a CCE student
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code OR (f.faculty_code = me.src AND f.programme_code IS NULL))
       AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND finance.pg_line(me.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, g.applies_category)   -- V391: a full-time line never reaches a postgraduate student
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)))
       AND (f.semester IS NULL OR f.semester <= p_semester);
$function$;

CREATE OR REPLACE FUNCTION finance.fee_sums(p_session text, p_semester integer)
 RETURNS TABLE(profile_key text, due_before numeric, due_upto numeric, fee numeric, late_payment numeric, late_registration numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT lower(home_state) AS home_state FROM finance.fee_setting WHERE id = 1),
    open_max AS (SELECT coalesce((SELECT max(sm.number) FROM policy.semester sm WHERE sm.session = p_session AND sm.state = 'OPEN'), 3) AS n),
    prof AS (SELECT x.*, fs.source_code AS src   -- V451: the faculty a profile is charged as, while a rule is in force
               FROM (SELECT DISTINCT pr.profile_key, pr.programme_code, pr.faculty_code, pr.category, pr.current_level, pr.entry_mode, pr.state, pr.is_spill, pr.spill_year, pr.final_level
                       FROM finance.fee_profiles() pr) x
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

-- the gap report (the return type changes)
DROP FUNCTION finance.fee_gaps(text);
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
                    ELSE coalesce(s.current_level > fl.final, false) END AS is_spill,
               CASE WHEN s.status = 'GRADUATED' THEN NULL
                    WHEN basis.b = 'COHORT' THEN CASE WHEN ap.spillover_state LIKE 'SPILLOVER%' THEN least(greatest(coalesce(ap.spillover_years, 1), 1), 3) END
                    WHEN s.current_level > fl.final THEN least((s.current_level - fl.final) / 100, 3) END AS spill_year,   -- V613
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

CREATE OR REPLACE FUNCTION finance.watch_fee_gaps(p_session text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE v_ses text := coalesce(p_session, policy.university_current_session()); v_keys text[]; v_new text[]; v_students bigint; v_groups int; v_list text;
        v_prev text[]; v_vars jsonb; v_at text; p record; told int := 0;
BEGIN
    -- only while a semester of the session (the current one, unless named) is open: a session not yet running is still being stated
    IF v_ses IS NULL OR NOT EXISTS (SELECT 1 FROM policy.semester WHERE session = v_ses AND state = 'OPEN') THEN
        RETURN 0;
    END IF;
    WITH g AS (SELECT * FROM finance.fee_gaps(v_ses)),
    fac AS (SELECT coalesce(g.faculty, g.faculty_code) AS f, sum(g.students) AS n FROM g GROUP BY 1)
    SELECT (SELECT coalesce(array_agg(x.k ORDER BY x.k), '{}'::text[])
              FROM (SELECT concat_ws('|', g.programme_code, g.level, g.entry_mode, g.indigene, g.spillover, g.spill_year, coalesce(g.missing::text, 'none')) AS k FROM g) x),
           (SELECT coalesce(sum(g.students), 0) FROM g),
           (SELECT count(*) FROM g),
           (SELECT string_agg(replace(replace(replace(initcap(lower(fac.f)), ' And ', ' and '), ' Of ', ' of '), ' For ', ' for ')
                              || ' ' || to_char(fac.n, 'FM999,999,999'), '; ' ORDER BY fac.n DESC, fac.f) FROM fac)
      INTO v_keys, v_students, v_groups, v_list;
    SELECT w.told_keys INTO v_prev FROM finance.fee_gap_watch w WHERE w.session = v_ses FOR UPDATE;
    v_new := ARRAY(SELECT k FROM unnest(v_keys) k WHERE NOT k = ANY (coalesce(v_prev, '{}'::text[])));
    IF cardinality(v_new) > 0 THEN
        v_at := to_char(clock_timestamp() AT TIME ZONE 'UTC', 'YYYYMMDDHH24MISSUS');   -- each telling its own event
        v_vars := jsonb_build_object('SESSION', v_ses, 'STUDENTS', to_char(v_students, 'FM999,999,999'), 'GROUPS', v_groups,
                                     'NEW_GROUPS', cardinality(v_new), 'FACULTIES', coalesce(v_list, ''));
        FOR p IN SELECT DISTINCT a.person_id
                   FROM iam.office_assignment a JOIN iam.person pe ON pe.id = a.person_id
                  WHERE a.office_code IN ('bursar', 'studentaccounts') AND pe.ended_on IS NULL
                    AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) LOOP
            told := told + platform.tell_person(p.person_id, 'FEE_GAPS', NULL, v_vars,
                                                'fee-gaps:' || v_ses || ':' || md5(array_to_string(v_new, ',')) || ':' || v_at, ARRAY['EMAIL', 'PORTAL', 'SMS']);
        END LOOP;
    END IF;
    -- the groups seen now are the ones told: a gap put right and opened again is told again
    INSERT INTO finance.fee_gap_watch AS w (session, told_keys, told_at, told, students, groups, checked_at)
    VALUES (v_ses, v_keys, CASE WHEN cardinality(v_new) > 0 THEN now() END, told, v_students, v_groups, now())
    ON CONFLICT (session) DO UPDATE
       SET told_keys = excluded.told_keys,
           told_at = coalesce(excluded.told_at, w.told_at),
           told = CASE WHEN excluded.told_at IS NOT NULL THEN excluded.told ELSE w.told END,
           students = excluded.students, groups = excluded.groups, checked_at = excluded.checked_at;
    RETURN told;
END $function$;

-- the writers
CREATE OR REPLACE FUNCTION finance.add_fee_lines(p_session text, p_rows jsonb)
 RETURNS TABLE(rows integer, added integer, no_amount integer, already integer, no_programme integer, charged_as integer, skipped integer, first_error text)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_prog text; v_fac text; v_level int; v_mode text; v_sem int; v_ind text; v_spill boolean; v_spill_year int; v_amt numeric; v_item text;
        n int := 0; na int := 0; nb int := 0; nal int := 0; nnp int := 0; nca int := 0; ns int := 0; v_err text;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'FEE_LINES_PERSON: fee lines are added by a person' USING ERRCODE = '23514'; END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_session) THEN
        RAISE EXCEPTION 'FEE_LINES_SESSION: % is not on the calendar', p_session USING ERRCODE = '23514';
    END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'FEE_LINES_ROWS: the sheet is rows: programme, level, entry mode, semester, indigeneship and the amount' USING ERRCODE = '23514';
    END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        n := n + 1;
        BEGIN
            v_amt := nullif(regexp_replace(coalesce(r->>'amount', ''), '[^0-9.]', '', 'g'), '')::numeric;
            IF v_amt IS NULL THEN nb := nb + 1; CONTINUE; END IF;
            -- a programme's line, or — with no programme — a faculty's line (the sheet asks for the faculty a
            -- "charged as" faculty follows, V451, so its own students and the faculty's are stated together)
            v_prog := nullif(upper(btrim(coalesce(r->>'programmeCode', r->>'programme_code', r->>'programme', ''))), '');
            v_fac := nullif(upper(btrim(coalesce(r->>'facultyCode', r->>'faculty_code', ''))), '');
            IF v_prog IS NOT NULL THEN
                SELECT p.code, p.faculty_code INTO v_prog, v_fac FROM ref.programme p WHERE upper(p.code) = v_prog;
                IF v_prog IS NULL THEN nnp := nnp + 1; CONTINUE; END IF;
                -- a line of its own would end the rule for every student of a faculty charged as another: refused here
                IF finance.fee_source_of(v_fac, p_session) IS NOT NULL THEN nca := nca + 1; CONTINUE; END IF;
            ELSE
                SELECT f.code INTO v_fac FROM ref.faculty f WHERE upper(f.code) = v_fac;
                IF v_fac IS NULL THEN nnp := nnp + 1; CONTINUE; END IF;
                IF finance.fee_source_of(v_fac, p_session) IS NOT NULL THEN nca := nca + 1; CONTINUE; END IF;
            END IF;
            -- V613: the Spillover cell says Yes (any spillover year) or SP1, SP2, SP3 (that year alone); a spillYear column likewise
            v_spill_year := finance.spill_year_of(r->>'spillover', coalesce(r->>'spillYear', r->>'spill_year'));
            v_spill := v_spill_year IS NOT NULL OR lower(btrim(coalesce(r->>'spillover', ''))) IN ('true', 't', '1', 'yes', 'y', 'spillover', 'spill');
            -- V613: a spillover line's level, where the sheet gives one, is the programme's final level (400 on a four-year programme)
            v_level := nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int;
            IF v_level IS NOT NULL AND v_level NOT IN (100, 200, 300, 400, 500, 600, 700, 800, 900) THEN v_level := NULL; END IF;
            v_mode := nullif(upper(replace(btrim(coalesce(r->>'entryMode', r->>'entry_mode', '')), ' ', '_')), '');
            IF v_mode IS NOT NULL AND v_mode NOT IN ('UTME', 'DIRECT_ENTRY', 'TRANSFER', 'POSTGRADUATE', 'JUPEB', 'SANDWICH') THEN v_mode := NULL; END IF;
            v_sem := nullif(regexp_replace(coalesce(r->>'semester', ''), '[^0-9]', '', 'g'), '')::int;
            IF v_sem IS NOT NULL AND v_sem NOT IN (1, 2, 3) THEN v_sem := NULL; END IF;
            v_ind := upper(btrim(coalesce(r->>'indigene', '')));
            v_ind := CASE WHEN v_ind LIKE 'NON%' OR v_ind LIKE 'NN%' THEN 'NON_INDIGENE' WHEN v_ind LIKE 'IND%' THEN 'INDIGENE' ELSE NULL END;
            -- a line the schedule already holds is not added twice
            IF EXISTS (SELECT 1 FROM finance.fee_schedule f
                        WHERE f.session = p_session AND f.ended_at IS NULL AND f.kind = 'FEE'
                          AND f.programme_code IS NOT DISTINCT FROM v_prog AND f.faculty_code IS NOT DISTINCT FROM v_fac
                          AND f.level IS NOT DISTINCT FROM v_level AND f.entry_mode IS NOT DISTINCT FROM v_mode
                          AND f.semester IS NOT DISTINCT FROM v_sem AND f.indigene IS NOT DISTINCT FROM v_ind AND f.spillover = v_spill AND f.spill_year IS NOT DISTINCT FROM v_spill_year) THEN
                nal := nal + 1; CONTINUE;
            END IF;
            v_item := CASE WHEN v_spill_year IS NOT NULL THEN 'School fees (spillover SP' || v_spill_year || ')' WHEN v_spill THEN 'School fees (spillover)' ELSE 'School fees' END
                      || CASE WHEN v_sem IS NULL THEN '' ELSE ' (semester ' || v_sem || ')' END;
            INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, semester, indigene, ord, spillover, spill_year, kind)
            VALUES (p_session, v_item, v_amt, v_level, v_mode, v_fac, v_prog, v_sem, v_ind,
                    coalesce(v_sem, 1) + CASE WHEN v_spill THEN 100 ELSE 0 END, v_spill, v_spill_year, 'FEE');
            na := na + 1;
        EXCEPTION WHEN OTHERS THEN
            ns := ns + 1;
            IF v_err IS NULL THEN v_err := left('row ' || n || ': ' || SQLERRM, 300); END IF;
        END;
    END LOOP;
    RETURN QUERY SELECT n, na, nb, nal, nnp, nca, ns, v_err;
END $function$;

CREATE OR REPLACE FUNCTION finance.import_fee_structure(p_session text, p_rows jsonb, p_scope text, p_confirm_whole boolean)
 RETURNS TABLE(rows integer, lines integer, faculties integer, no_faculty integer, no_programme integer, no_group integer, spillover integer, programmes integer)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_scope text := upper(btrim(coalesce(p_scope, 'SESSION')));
        v_fac text; v_fac_code text; v_level int; v_mode text; v_sem int; v_ind text; v_amt numeric; v_item text; v_ord int;
        v_spill boolean; v_spill_year int; v_prog text; v_prog_code text; v_grp text; v_grp_code text; v_kind text; v_cce boolean; v_full boolean;
        n int := 0; nl int := 0; nnf int := 0; nnp int := 0; nng int := 0; nsp int := 0; facs text[] := '{}'; progs text[] := '{}';
        v_unknown text[] := '{}'; v_row_facs text[] := '{}'; v_row_progs text[] := '{}'; v_prog_facs text[] := '{}'; v_universal boolean := false;
        v_left text; v_left_lines int;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a fees structure is uploaded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the structure is rows: faculty or programme, level, semester, indigeneship and the amount' USING ERRCODE = '23514';
    END IF;
    IF v_scope NOT IN ('SESSION', 'LISTED') THEN
        RAISE EXCEPTION 'FEE_STRUCTURE_SCOPE: a structure replaces the whole session (SESSION) or only the faculties and programmes it names (LISTED)' USING ERRCODE = '23514';
    END IF;
    v_cce := EXISTS (SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE upper(btrim(coalesce(x->>'entryMode', x->>'entry_mode', ''))) = 'CCE');
    v_full := EXISTS (SELECT 1 FROM jsonb_array_elements(p_rows) x WHERE upper(btrim(coalesce(x->>'entryMode', x->>'entry_mode', ''))) <> 'CCE');

    -- V535: what the file names, before anything changes — every name held, and the faculties and programmes it states
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_amt := nullif(regexp_replace(coalesce(r->>'amount', ''), '[^0-9.]', '', 'g'), '')::numeric;
        IF v_amt IS NULL OR v_amt < 0 THEN CONTINUE; END IF;
        v_fac := btrim(coalesce(r->>'faculty', r->>'facultyCode', r->>'faculty_code', ''));
        v_prog := btrim(coalesce(r->>'programmeCode', r->>'programme_code', r->>'programme', r->>'program', ''));
        v_fac_code := NULL; v_prog_code := NULL;
        IF v_prog <> '' THEN
            SELECT code INTO v_prog_code FROM ref.programme WHERE upper(code) = upper(v_prog);
            IF v_prog_code IS NULL THEN SELECT code INTO v_prog_code FROM ref.programme WHERE upper(name) = upper(v_prog) ORDER BY archived LIMIT 1; END IF;
            IF v_prog_code IS NULL THEN
                IF NOT ('programme ' || v_prog = ANY (v_unknown)) THEN v_unknown := v_unknown || ('programme ' || v_prog); END IF;
            ELSE
                IF NOT (v_prog_code = ANY (v_row_progs)) THEN v_row_progs := v_row_progs || v_prog_code; END IF;
                SELECT faculty_code INTO v_fac_code FROM ref.programme WHERE code = v_prog_code;
                IF v_fac_code IS NOT NULL AND NOT (v_fac_code = ANY (v_prog_facs)) THEN v_prog_facs := v_prog_facs || v_fac_code; END IF;
            END IF;
        ELSIF v_fac <> '' THEN
            SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(code) = upper(v_fac);
            IF v_fac_code IS NULL THEN SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(name) = upper(v_fac) LIMIT 1; END IF;
            IF v_fac_code IS NULL THEN SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(name) LIKE '%' || upper(v_fac) || '%' LIMIT 1; END IF;
            IF v_fac_code IS NULL THEN
                IF NOT ('faculty ' || v_fac = ANY (v_unknown)) THEN v_unknown := v_unknown || ('faculty ' || v_fac); END IF;
            ELSIF NOT (v_fac_code = ANY (v_row_facs)) THEN v_row_facs := v_row_facs || v_fac_code;
            END IF;
        ELSE
            v_universal := true;
        END IF;
    END LOOP;
    IF cardinality(v_unknown) > 0 THEN
        RAISE EXCEPTION 'FEE_STRUCTURE_UNKNOWN: the file names % that the portal does not hold; nothing was changed — correct the name or use the code',
            array_to_string(v_unknown, ', ') USING ERRCODE = '23514';
    END IF;

    IF v_scope = 'SESSION' THEN
        -- V535: the whole session is replaced only on purpose when the file leaves a faculty out
        SELECT string_agg(coalesce(fa.name, x.faculty_code) || ' (' || x.n || CASE WHEN x.n = 1 THEN ' line' ELSE ' lines' END || ')', ', ' ORDER BY coalesce(fa.name, x.faculty_code)), sum(x.n)
          INTO v_left, v_left_lines
          FROM (SELECT f.faculty_code, count(*) AS n FROM finance.fee_schedule f
                 WHERE f.session = p_session AND f.ended_at IS NULL AND f.faculty_code IS NOT NULL
                   AND ((v_cce AND f.entry_mode = 'CCE') OR (v_full AND f.entry_mode IS DISTINCT FROM 'CCE'))
                   AND NOT (f.faculty_code = ANY (v_row_facs || v_prog_facs))
                 GROUP BY f.faculty_code) x
          LEFT JOIN ref.faculty fa ON fa.code = x.faculty_code;
        IF v_left IS NOT NULL AND NOT coalesce(p_confirm_whole, false) THEN
            RAISE EXCEPTION 'FEE_STRUCTURE_PARTIAL: this file states no fee for %; as the whole session it would end those % fee lines in force — upload it for the faculties and programmes in the file only, or confirm that the whole session is replaced',
                v_left, v_left_lines USING ERRCODE = '23514';
        END IF;
        -- replace the session's approved structure: end what stands, then load the new. V380: only the lines of the upload's own
        -- kind — a CCE (part-time) structure replaces the CCE lines, a full-time structure every other line
        UPDATE finance.fee_schedule SET ended_at = now()
         WHERE session = p_session AND ended_at IS NULL
           AND ((v_cce AND entry_mode = 'CCE') OR (v_full AND entry_mode IS DISTINCT FROM 'CCE'));
    ELSE
        -- V535: only what the file names — a programme's lines, a faculty's own lines, the University-wide lines — of its kind
        UPDATE finance.fee_schedule SET ended_at = now()
         WHERE session = p_session AND ended_at IS NULL
           AND ((v_cce AND entry_mode = 'CCE') OR (v_full AND entry_mode IS DISTINCT FROM 'CCE'))
           AND (programme_code = ANY (v_row_progs)
                OR (programme_code IS NULL AND faculty_code = ANY (v_row_facs))
                OR (v_universal AND programme_code IS NULL AND faculty_code IS NULL));
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_amt := nullif(regexp_replace(coalesce(r->>'amount', ''), '[^0-9.]', '', 'g'), '')::numeric;
        IF v_amt IS NULL OR v_amt < 0 THEN CONTINUE; END IF;
        n := n + 1;

        -- the faculty, by code or name
        v_fac := btrim(coalesce(r->>'faculty', r->>'facultyCode', r->>'faculty_code', ''));
        v_fac_code := NULL;
        IF v_fac <> '' THEN
            SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(code) = upper(v_fac);
            IF v_fac_code IS NULL THEN SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(name) = upper(v_fac) LIMIT 1; END IF;
            IF v_fac_code IS NULL THEN SELECT code INTO v_fac_code FROM ref.faculty WHERE upper(name) LIKE '%' || upper(v_fac) || '%' LIMIT 1; END IF;
            IF v_fac_code IS NULL THEN nnf := nnf + 1; END IF;
        END IF;

        -- the programme, by code or name: the line is that programme's alone
        v_prog := btrim(coalesce(r->>'programmeCode', r->>'programme_code', r->>'programme', r->>'program', ''));
        v_prog_code := NULL;
        IF v_prog <> '' THEN
            SELECT code INTO v_prog_code FROM ref.programme WHERE upper(code) = upper(v_prog);
            IF v_prog_code IS NULL THEN SELECT code INTO v_prog_code FROM ref.programme WHERE upper(name) = upper(v_prog) ORDER BY archived LIMIT 1; END IF;
            IF v_prog_code IS NULL THEN nnp := nnp + 1; END IF;
            -- a programme names its faculty; the faculty column is not needed beside it
            IF v_prog_code IS NOT NULL AND v_fac_code IS NULL THEN SELECT faculty_code INTO v_fac_code FROM ref.programme WHERE code = v_prog_code; END IF;
        END IF;

        -- the fee group, by code or name
        v_grp := btrim(coalesce(r->>'feeGroup', r->>'fee_group', r->>'group', ''));
        v_grp_code := NULL;
        IF v_grp <> '' THEN
            SELECT code INTO v_grp_code FROM ref.fee_group WHERE upper(code) = upper(v_grp);
            IF v_grp_code IS NULL THEN SELECT code INTO v_grp_code FROM ref.fee_group WHERE upper(name) = upper(v_grp) LIMIT 1; END IF;
            IF v_grp_code IS NULL THEN nng := nng + 1; END IF;
        END IF;

        v_level := nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int;
        IF v_level IS NOT NULL AND v_level NOT IN (100,200,300,400,500,600,700,800,900) THEN v_level := NULL; END IF;
        v_mode := nullif(upper(replace(btrim(coalesce(r->>'entryMode', r->>'entry_mode', '')), ' ', '_')), '');
        IF v_mode IS NOT NULL AND v_mode NOT IN ('UTME','DIRECT_ENTRY','TRANSFER','POSTGRADUATE','JUPEB','SANDWICH','CCE') THEN v_mode := NULL; END IF;
        v_sem := nullif(regexp_replace(coalesce(r->>'semester', ''), '[^0-9]', '', 'g'), '')::int;
        IF v_sem IS NOT NULL AND v_sem NOT IN (1,2,3) THEN v_sem := NULL; END IF;
        v_ind := upper(btrim(coalesce(r->>'indigene', '')));
        v_ind := CASE WHEN v_ind LIKE 'IND%' THEN 'INDIGENE' WHEN v_ind LIKE 'NON%' OR v_ind LIKE 'NN%' THEN 'NON_INDIGENE' ELSE NULL END;
        v_spill_year := finance.spill_year_of(r->>'spillover', coalesce(r->>'spillYear', r->>'spill_year'));   -- V613: SP1, SP2, SP3
        v_spill := v_spill_year IS NOT NULL OR lower(btrim(coalesce(r->>'spillover', 'false'))) IN ('true', 't', '1', 'yes', 'y', 'spillover', 'spill');
        -- V613: a spillover line keeps the level the sheet gives it — the programme's final level — or has none and reaches every programme (V088)
        IF v_spill THEN nsp := nsp + 1; END IF;
        v_kind := upper(regexp_replace(btrim(coalesce(r->>'kind', r->>'type', '')), '[^A-Za-z]', '', 'g'));
        v_kind := CASE WHEN v_kind LIKE 'LATEPAY%' THEN 'LATE_PAYMENT' WHEN v_kind LIKE 'LATEREG%' THEN 'LATE_REGISTRATION' ELSE 'FEE' END;
        v_item := nullif(btrim(coalesce(r->>'item', '')), '');
        IF v_item IS NULL THEN
            v_item := CASE v_kind WHEN 'LATE_PAYMENT' THEN 'Late payment fee' WHEN 'LATE_REGISTRATION' THEN 'Late registration fee'
                                  ELSE CASE WHEN v_spill_year IS NOT NULL THEN 'School fees (spillover SP' || v_spill_year || ')' WHEN v_spill THEN 'School fees (spillover)' ELSE 'School fees' END END
                      || CASE WHEN v_sem IS NULL THEN '' ELSE ' (semester ' || v_sem || ')' END;
        END IF;
        v_ord := coalesce(nullif(regexp_replace(coalesce(r->>'ord', r->>'order', ''), '[^0-9]', '', 'g'), '')::int,
                          coalesce(v_sem, 1) + CASE WHEN v_spill THEN 100 ELSE 0 END);

        INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, fee_group, semester, indigene, ord, spillover, spill_year, kind)
        VALUES (p_session, v_item, v_amt, v_level, v_mode, v_fac_code, v_prog_code, v_grp_code, v_sem, v_ind, v_ord, v_spill, v_spill_year, v_kind);
        nl := nl + 1;
        IF v_fac_code IS NOT NULL AND NOT (v_fac_code = ANY(facs)) THEN facs := facs || v_fac_code; END IF;
        IF v_prog_code IS NOT NULL AND NOT (v_prog_code = ANY(progs)) THEN progs := progs || v_prog_code; END IF;
    END LOOP;
    RETURN QUERY SELECT n, nl, cardinality(facs), nnf, nnp, nng, nsp, cardinality(progs);
END $function$;

DROP FUNCTION finance.copy_session_fees(text, text, boolean);
CREATE OR REPLACE FUNCTION finance.copy_session_fees(p_from text, p_to text, p_apply boolean)
 RETURNS TABLE(item text, kind text, amount numeric, level integer, entry_mode text, faculty_code text, programme_code text, fee_group text, semester integer, indigene text, spillover boolean, spill_year integer, ord integer, target_amount numeric, action text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF p_from IS NULL OR p_to IS NULL OR p_from = p_to THEN
        RAISE EXCEPTION 'FEE_COPY_SESSIONS: copy from one session into another' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_to) THEN
        RAISE EXCEPTION 'FEE_COPY_SESSION: % is not a session on the calendar', p_to USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM finance.fee_schedule f WHERE f.session = p_from AND f.ended_at IS NULL) THEN
        RAISE EXCEPTION 'FEE_COPY_EMPTY: % states no fee line to copy', p_from USING ERRCODE = '23514';
    END IF;
    IF p_apply AND nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'FEE_COPY_ACTOR: fees are copied by a person' USING ERRCODE = '23514';
    END IF;
    -- what each line of the source is to the target (read before anything is copied, so the answer says what the copy did);
    -- a preview writes nothing, and reads in a read-only transaction
    RETURN QUERY
    SELECT s.item, s.kind, s.amount, s.level, s.entry_mode, s.faculty_code, s.programme_code, s.fee_group, s.semester, s.indigene, s.spillover, s.spill_year, s.ord,
           t.amount, CASE WHEN t.amount IS NULL THEN 'COPY' ELSE 'KEPT' END
      FROM finance.fee_schedule s
      LEFT JOIN LATERAL (SELECT x.amount FROM finance.fee_schedule x WHERE x.session = p_to AND x.ended_at IS NULL AND finance.fee_line_same_scope(x, s) LIMIT 1) t ON true
     WHERE s.session = p_from AND s.ended_at IS NULL
     ORDER BY s.kind, s.ord, s.item, s.faculty_code NULLS FIRST, s.programme_code NULLS FIRST, s.level NULLS FIRST, s.semester NULLS FIRST;
    IF p_apply THEN
        INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, ord, fee_group, semester, indigene, spillover, spill_year, kind)
        SELECT p_to, s.item, s.amount, s.level, s.entry_mode, s.faculty_code, s.programme_code, s.ord, s.fee_group, s.semester, s.indigene, s.spillover, s.spill_year, s.kind
          FROM finance.fee_schedule s
         WHERE s.session = p_from AND s.ended_at IS NULL
           AND NOT EXISTS (SELECT 1 FROM finance.fee_schedule x WHERE x.session = p_to AND x.ended_at IS NULL AND finance.fee_line_same_scope(x, s));
    END IF;
END $function$;

DROP FUNCTION finance.copy_spillover_lines(text, text, boolean);
CREATE OR REPLACE FUNCTION finance.copy_spillover_lines(p_from text, p_to text, p_apply boolean)
 RETURNS TABLE(item text, kind text, amount numeric, level integer, entry_mode text, faculty_code text, programme_code text, fee_group text, semester integer, indigene text, spillover boolean, spill_year integer, ord integer, target_amount numeric, action text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF p_from IS NULL OR p_to IS NULL OR p_from = p_to THEN
        RAISE EXCEPTION 'FEE_COPY_SESSIONS: copy from one session into another' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_to) THEN
        RAISE EXCEPTION 'FEE_COPY_SESSION: % is not a session on the calendar', p_to USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM finance.fee_schedule f WHERE f.session = p_from AND f.ended_at IS NULL AND f.spillover) THEN
        RAISE EXCEPTION 'FEE_COPY_EMPTY: % states no spillover line to copy', p_from USING ERRCODE = '23514';
    END IF;
    IF p_apply AND nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'FEE_COPY_ACTOR: fees are copied by a person' USING ERRCODE = '23514';
    END IF;
    RETURN QUERY
    SELECT s.item, s.kind, s.amount, s.level, s.entry_mode, s.faculty_code, s.programme_code, s.fee_group, s.semester, s.indigene, s.spillover, s.spill_year, s.ord,
           t.amount, CASE WHEN t.amount IS NULL THEN 'COPY' ELSE 'KEPT' END
      FROM finance.fee_schedule s
      LEFT JOIN LATERAL (SELECT x.amount FROM finance.fee_schedule x WHERE x.session = p_to AND x.ended_at IS NULL AND finance.fee_line_same_scope(x, s) LIMIT 1) t ON true
     WHERE s.session = p_from AND s.ended_at IS NULL AND s.spillover
     ORDER BY s.kind, s.ord, s.item, s.faculty_code NULLS FIRST, s.programme_code NULLS FIRST, s.level NULLS FIRST, s.semester NULLS FIRST;
    IF p_apply THEN
        INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, ord, fee_group, semester, indigene, spillover, spill_year, kind)
        SELECT p_to, s.item, s.amount, s.level, s.entry_mode, s.faculty_code, s.programme_code, s.ord, s.fee_group, s.semester, s.indigene, s.spillover, s.spill_year, s.kind
          FROM finance.fee_schedule s
         WHERE s.session = p_from AND s.ended_at IS NULL AND s.spillover
           AND NOT EXISTS (SELECT 1 FROM finance.fee_schedule x WHERE x.session = p_to AND x.ended_at IS NULL AND finance.fee_line_same_scope(x, s));
    END IF;
END $function$;

CREATE OR REPLACE FUNCTION finance.copy_faculty_fees(p_from text, p_to text, p_session text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE n int;
BEGIN
    IF p_from IS NULL OR p_to IS NULL OR p_from = p_to
       OR NOT EXISTS (SELECT 1 FROM ref.faculty WHERE code = p_from) OR NOT EXISTS (SELECT 1 FROM ref.faculty WHERE code = p_to) THEN
        RETURN 0;
    END IF;
    -- a faculty the Bursary has already stated for the session is left as it is
    IF EXISTS (SELECT 1 FROM finance.fee_schedule f WHERE f.session = p_session AND f.faculty_code = p_to AND f.ended_at IS NULL) THEN
        RETURN 0;
    END IF;
    INSERT INTO finance.fee_schedule (id, session, item, amount, level, entry_mode, faculty_code, programme_code, ord, fee_group, semester, indigene, spillover, spill_year, kind)
    SELECT gen_random_uuid(), f.session, f.item, f.amount, f.level, f.entry_mode, p_to, NULL, f.ord, f.fee_group, f.semester, f.indigene, f.spillover, f.spill_year, f.kind
      FROM finance.fee_schedule f
     WHERE f.session = p_session AND f.faculty_code = p_from AND f.programme_code IS NULL AND f.ended_at IS NULL;
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $function$;

CREATE OR REPLACE FUNCTION finance.copy_programme_lines(p_from_session text, p_from_programme text, p_from_level integer, p_to_session text, p_to_programme text, p_to_level integer, p_apply boolean)
 RETURNS TABLE(item text, kind text, amount numeric, entry_mode text, fee_group text, semester integer, indigene text, ord integer, target_amount numeric, action text)
 LANGUAGE plpgsql
AS $function$
DECLARE v_faculty text;
BEGIN
    IF p_to_level IS NULL OR p_to_level NOT IN (100, 200, 300, 400, 500, 600, 700, 800, 900) OR p_from_level IS NULL THEN
        RAISE EXCEPTION 'FEE_LEVEL: lines are copied from one level into one level (100 to 900)' USING ERRCODE = '23514';
    END IF;
    SELECT faculty_code INTO v_faculty FROM ref.programme WHERE code = p_to_programme;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'FEE_COPY_PROGRAMME: % is not a programme on the register', p_to_programme USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_to_session) THEN
        RAISE EXCEPTION 'FEE_COPY_SESSION: % is not a session on the calendar', p_to_session USING ERRCODE = '23514';
    END IF;
    IF p_from_session = p_to_session AND p_from_programme = p_to_programme AND p_from_level = p_to_level THEN
        RAISE EXCEPTION 'FEE_COPY_SESSIONS: copy from one programme or level into another' USING ERRCODE = '23514';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM finance.programme_level_lines(p_from_session, p_from_programme, p_from_level)) THEN
        RAISE EXCEPTION 'FEE_COPY_EMPTY: % states no line for % at % Level', p_from_session, p_from_programme, p_from_level USING ERRCODE = '23514';
    END IF;
    IF p_apply AND nullif(current_setting('moaum.actor_id', true), '') IS NULL THEN
        RAISE EXCEPTION 'FEE_COPY_ACTOR: fees are copied by a person' USING ERRCODE = '23514';
    END IF;
    -- each source line as the target programme's own line at the target level (its faculty kept where the line named one), and
    -- the line the target already states for the same students (finance.fee_line_same_scope's columns); nothing written unless applied
    RETURN QUERY
    SELECT s.item, s.kind, s.amount, s.entry_mode, s.fee_group, s.semester, s.indigene, s.ord, t.amount,
           CASE WHEN t.amount IS NULL THEN 'COPY' ELSE 'KEPT' END
      FROM finance.programme_level_lines(p_from_session, p_from_programme, p_from_level) s
      LEFT JOIN LATERAL (SELECT x.amount FROM finance.fee_schedule x
                          WHERE x.session = p_to_session AND x.ended_at IS NULL AND NOT x.spillover
                            AND lower(btrim(x.item)) = lower(btrim(s.item)) AND x.kind = s.kind AND x.level = p_to_level AND x.programme_code = p_to_programme
                            AND x.faculty_code IS NOT DISTINCT FROM (CASE WHEN s.faculty_code IS NULL THEN NULL ELSE v_faculty END)
                            AND x.entry_mode IS NOT DISTINCT FROM s.entry_mode AND x.fee_group IS NOT DISTINCT FROM s.fee_group
                            AND x.semester IS NOT DISTINCT FROM s.semester AND x.indigene IS NOT DISTINCT FROM s.indigene
                          LIMIT 1) t ON true;
    IF p_apply THEN
        INSERT INTO finance.fee_schedule (session, item, amount, level, entry_mode, faculty_code, programme_code, ord, fee_group, semester, indigene, spillover, spill_year, kind)
        SELECT p_to_session, s.item, s.amount, p_to_level, s.entry_mode, CASE WHEN s.faculty_code IS NULL THEN NULL ELSE v_faculty END, p_to_programme,
               s.ord, s.fee_group, s.semester, s.indigene, false, NULL, s.kind
          FROM finance.programme_level_lines(p_from_session, p_from_programme, p_from_level) s
         WHERE NOT EXISTS (SELECT 1 FROM finance.fee_schedule x
                            WHERE x.session = p_to_session AND x.ended_at IS NULL AND NOT x.spillover
                              AND lower(btrim(x.item)) = lower(btrim(s.item)) AND x.kind = s.kind AND x.level = p_to_level AND x.programme_code = p_to_programme
                              AND x.faculty_code IS NOT DISTINCT FROM (CASE WHEN s.faculty_code IS NULL THEN NULL ELSE v_faculty END)
                              AND x.entry_mode IS NOT DISTINCT FROM s.entry_mode AND x.fee_group IS NOT DISTINCT FROM s.fee_group
                              AND x.semester IS NOT DISTINCT FROM s.semester AND x.indigene IS NOT DISTINCT FROM s.indigene);
    END IF;
END $function$;

CREATE OR REPLACE FUNCTION finance.fee_upload_effect(p_session text, p_rows jsonb, p_action text, p_scope text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE v_before jsonb; v_gaps_before jsonb; v_res jsonb; v_out jsonb; v_msg text; v_action text := upper(btrim(coalesce(p_action, '')));
BEGIN
    IF v_action NOT IN ('STRUCTURE', 'LINES', 'CLEAR') THEN
        RAISE EXCEPTION 'FEE_UPLOAD_ACTION: an upload is the structure (STRUCTURE) or the fees to state (LINES); clearing is CLEAR' USING ERRCODE = '23514';
    END IF;
    SELECT coalesce(jsonb_agg(to_jsonb(f)), '[]'::jsonb) INTO v_before
      FROM (SELECT id, faculty_code, programme_code, level, entry_mode, semester, indigene, spillover, spill_year, kind, fee_group, item, amount
              FROM finance.fee_schedule WHERE session = p_session AND ended_at IS NULL) f;
    SELECT jsonb_build_object('students', coalesce(sum(g.students), 0), 'groups', count(*)) INTO v_gaps_before FROM finance.fee_gaps(p_session) g;
    BEGIN
        IF v_action = 'LINES' THEN
            SELECT to_jsonb(x) INTO v_res FROM finance.add_fee_lines(p_session, p_rows) x;
        ELSIF v_action = 'CLEAR' THEN
            -- V547: what "Clear the schedule" would end — every line of the session, or its full-time or its CCE lines alone
            WITH ended AS (
                UPDATE finance.fee_schedule SET ended_at = now()
                 WHERE session = p_session AND ended_at IS NULL
                   AND CASE upper(coalesce(p_scope, 'ALL')) WHEN 'CCE' THEN entry_mode = 'CCE'
                                                           WHEN 'FULL_TIME' THEN entry_mode IS DISTINCT FROM 'CCE' ELSE true END
                RETURNING 1)
            -- the live students of that kind, who would owe no school fee for the session (the gap list says nothing once a
            -- session states no line at all)
            SELECT jsonb_build_object('ended', (SELECT count(*) FROM ended),
                     'students', (SELECT count(*) FROM people.student st JOIN ref.programme pr ON pr.code = st.programme_code
                                   WHERE st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
                                     AND CASE upper(coalesce(p_scope, 'ALL')) WHEN 'CCE' THEN st.entry_mode = 'CCE'
                                              WHEN 'FULL_TIME' THEN st.entry_mode IS DISTINCT FROM 'CCE' ELSE true END))
              INTO v_res;
        ELSE
            SELECT to_jsonb(x) INTO v_res FROM finance.import_fee_structure(p_session, p_rows, coalesce(p_scope, 'LISTED'), true) x;
        END IF;
        WITH b AS (
            SELECT * FROM jsonb_to_recordset(v_before) AS x(id uuid, faculty_code text, programme_code text, level int, entry_mode text, semester int,
                                                              indigene text, spillover boolean, spill_year int, kind text, fee_group text, item text, amount numeric)),
        a AS (
            SELECT id, faculty_code, programme_code, level, entry_mode, semester, indigene, spillover, spill_year, kind, fee_group, item, amount
              FROM finance.fee_schedule WHERE session = p_session AND ended_at IS NULL),
        ended AS (SELECT b.*, row(b.faculty_code, b.programme_code, b.level, b.entry_mode, b.semester, b.indigene, b.spillover, b.spill_year, b.kind, b.fee_group, lower(btrim(b.item)))::text AS k
                    FROM b WHERE NOT EXISTS (SELECT 1 FROM a WHERE a.id = b.id)),
        added AS (SELECT a.*, row(a.faculty_code, a.programme_code, a.level, a.entry_mode, a.semester, a.indigene, a.spillover, a.spill_year, a.kind, a.fee_group, lower(btrim(a.item)))::text AS k
                    FROM a WHERE NOT EXISTS (SELECT 1 FROM b WHERE b.id = a.id)),
        pairs AS (
            SELECT coalesce(d.faculty_code, e.faculty_code) AS faculty_code, coalesce(d.programme_code, e.programme_code) AS programme_code,
                   coalesce(d.level, e.level) AS level, coalesce(d.entry_mode, e.entry_mode) AS entry_mode, coalesce(d.semester, e.semester) AS semester,
                   coalesce(d.indigene, e.indigene) AS indigene, coalesce(d.spillover, e.spillover) AS spillover, coalesce(d.spill_year, e.spill_year) AS spill_year, coalesce(d.item, e.item) AS item,
                   e.amount AS old, d.amount AS new,
                   CASE WHEN e.k IS NULL THEN 'NEW' WHEN d.k IS NULL THEN 'ENDED' WHEN e.amount = d.amount THEN 'SAME' ELSE 'CHANGED' END AS what
              FROM ended e FULL JOIN added d ON d.k = e.k),
        named AS (
            SELECT p.*, coalesce(fa.name, p.faculty_code, 'Every faculty') AS faculty, pr.name AS programme
              FROM pairs p LEFT JOIN ref.faculty fa ON fa.code = p.faculty_code LEFT JOIN ref.programme pr ON pr.code = p.programme_code),
        grp AS (
            SELECT n.faculty, n.faculty_code, n.programme, n.programme_code,
                   count(*) FILTER (WHERE n.what = 'NEW') AS new, count(*) FILTER (WHERE n.what = 'CHANGED') AS changed,
                   count(*) FILTER (WHERE n.what = 'SAME') AS same, count(*) FILTER (WHERE n.what = 'ENDED') AS ended
              FROM named n GROUP BY 1, 2, 3, 4),
        kept AS (   -- of each faculty or programme the upload touches, the lines that stay in force as they were
            SELECT a.faculty_code, a.programme_code, count(*) AS n FROM a WHERE NOT EXISTS (SELECT 1 FROM added d WHERE d.id = a.id) GROUP BY 1, 2),
        gaps AS (SELECT * FROM finance.fee_gaps(p_session))
        SELECT jsonb_build_object(
            'action', v_action, 'scope', CASE WHEN v_action = 'STRUCTURE' THEN coalesce(upper(p_scope), 'LISTED') WHEN v_action = 'CLEAR' THEN coalesce(upper(p_scope), 'ALL') END, 'result', v_res,
            'linesBefore', jsonb_array_length(v_before), 'linesAfter', (SELECT count(*) FROM a),
            'totals', (SELECT jsonb_build_object('new', coalesce(sum(new), 0), 'changed', coalesce(sum(changed), 0), 'same', coalesce(sum(same), 0), 'ended', coalesce(sum(ended), 0)) FROM grp),
            'groups', (SELECT coalesce(jsonb_agg(jsonb_build_object('faculty', g.faculty, 'facultyCode', g.faculty_code, 'programme', g.programme, 'programmeCode', g.programme_code,
                                                                     'new', g.new, 'changed', g.changed, 'same', g.same, 'ended', g.ended,
                                                                     'losesAll', g.ended > 0 AND g.new + g.changed + g.same = 0
                                                                                 AND NOT EXISTS (SELECT 1 FROM kept k WHERE k.faculty_code IS NOT DISTINCT FROM g.faculty_code
                                                                                                                         AND k.programme_code IS NOT DISTINCT FROM g.programme_code))
                                                  ORDER BY g.faculty, g.programme NULLS FIRST), '[]'::jsonb) FROM grp g),
            'changes', (SELECT coalesce(jsonb_agg(c ORDER BY c->>'faculty', c->>'programme', (c->>'semester')::int NULLS FIRST, (c->>'level')::int NULLS LAST), '[]'::jsonb)
                          FROM (SELECT jsonb_build_object('faculty', n.faculty, 'programme', n.programme, 'level', n.level, 'entryMode', n.entry_mode, 'semester', n.semester,
                                                          'indigene', n.indigene, 'spillover', n.spillover, 'spillYear', n.spill_year, 'item', n.item, 'old', n.old, 'new', n.new) AS c
                                  FROM named n WHERE n.what = 'CHANGED' ORDER BY n.faculty, n.programme, n.semester, n.level LIMIT 400) x),
            'gaps', jsonb_build_object(
                'before', v_gaps_before,
                'after', (SELECT jsonb_build_object('students', coalesce(sum(students), 0), 'groups', count(*)) FROM gaps),
                'rows', (SELECT coalesce(jsonb_agg(jsonb_build_object('faculty', coalesce(x.faculty, x.faculty_code), 'programme', x.programme, 'level', x.level,
                                                                      'entryMode', x.entry_mode, 'spillover', x.spillover, 'spillYear', x.spill_year, 'finalLevel', x.final_level, 'students', x.students)
                                                    ORDER BY x.students DESC), '[]'::jsonb)
                           FROM (SELECT * FROM gaps ORDER BY students DESC LIMIT 60) x)))
          INTO v_out;
        RAISE EXCEPTION 'FEE_UPLOAD_PREVIEW_UNDO';
    EXCEPTION WHEN raise_exception THEN
        GET STACKED DIAGNOSTICS v_msg = MESSAGE_TEXT;
        IF v_msg <> 'FEE_UPLOAD_PREVIEW_UNDO' THEN RAISE; END IF;
    END;
    RETURN v_out;
END $function$;

COMMENT ON FUNCTION finance.charges_of_as(uuid, text, text[], text) IS
    'what a student is charged for a session, line by line, as the programme named (V451 charged-as rule, V391 PG lines, V571 spillover basis, V613 spillover year: on a spillover line the level is the programme''s final level and spill_year the year, NULL for any)';
COMMENT ON FUNCTION finance.fee_gaps(text) IS
    'V451, V461, V571, V613: the groups of live undergraduates with no school-fee line for the session — by programme, level, entry mode, indigeneship, spillover and (V613) spillover year with the programme''s final level — with the faculty they are charged as, whether any line is stated and the open semesters none is stated for';

COMMIT;
