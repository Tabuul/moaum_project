-- V447 — The live PG students with no fee line stated, asked once per group of alike students rather than once per student.
--
--   finance.pg_unstated (V393) called finance.fee_stated for every live PG student. admissions.pg_readiness() reads it, and
--   the public /api/v1/platform/status read pg_readiness on every call: on live data, 3,453 PG students cost about 15 s a
--   call, and the status probes became almost all of the database's load.
--
--   finance.fee_stated (V391) reads only these facts of a student: the programme, the current level (and through the
--   programme's final level, whether the student is a spill-over), the entry mode, and whether the state of origin is the
--   University's home state. Students alike in all four get the same answer, so the real function is asked once per
--   group, for one student of it, and the answer is counted for the whole group. The answers are the same as before, by
--   construction: nothing about the fee lines is re-stated here.
--
--   If finance.fee_stated ever reads another fact of the student, that fact joins the group here (check.sql compares the
--   two ways of counting).

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V447: the unstated PG students counted once per group of alike students', true);

CREATE OR REPLACE FUNCTION finance.pg_unstated(p_session text)
RETURNS TABLE (level integer, programme_code text, programme text, students bigint)
LANGUAGE sql STABLE AS $fn$
    WITH live AS (
        -- the live PG students, with the facts finance.fee_stated reads of a student (the state of origin as it reads it)
        SELECT s.id, s.current_level, s.programme_code, p.name, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) = lower(h.home_state) AS indigene
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code
          LEFT JOIN admissions.candidate c ON c.id = s.candidate_id
          LEFT JOIN admissions.caps_row r ON r.id = c.admitted_from
          LEFT JOIN finance.fee_setting h ON h.id = 1
         WHERE people.is_postgraduate(s.entry_mode, p.category)
           AND s.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')),
    alike AS (
        -- one student of each group of alike students, asked the real question
        SELECT g.programme_code, g.current_level, g.entry_mode, g.indigene, finance.fee_stated(g.one, p_session) AS stated
          FROM (SELECT l.programme_code, l.current_level, l.entry_mode, l.indigene, (array_agg(l.id))[1] AS one
                  FROM live l
                 GROUP BY l.programme_code, l.current_level, l.entry_mode, l.indigene) g)
    SELECT l.current_level, l.programme_code, l.name, count(*)
      FROM live l
      JOIN alike a ON a.programme_code = l.programme_code
                  AND a.current_level IS NOT DISTINCT FROM l.current_level
                  AND a.entry_mode IS NOT DISTINCT FROM l.entry_mode
                  AND a.indigene IS NOT DISTINCT FROM l.indigene
     WHERE NOT a.stated
     GROUP BY l.current_level, l.programme_code, l.name
     ORDER BY l.current_level, l.programme_code;
$fn$;
COMMENT ON FUNCTION finance.pg_unstated(text) IS
  'V393, V447: the live PG students (admitted, active, on probation) with no fee line stated for a session, by level and programme — the lines the Bursary has still to state (V391). finance.fee_stated is asked once per group of students alike in what it reads (programme, level, entry mode, home-state origin).';

COMMIT;
