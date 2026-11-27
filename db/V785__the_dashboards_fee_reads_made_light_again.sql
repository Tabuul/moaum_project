-- V785. The student dashboard's fee reads made light again.
--
-- What happened. On 27 November 2026, from about 13:40 (12:40 UTC), the portal timed out (504) for students: the database's load rose from
-- about 8 to 110–134, nearly all of it finance.due_for_semester (about 60%) and finance.spillover_panel (about 30%), writing large
-- temporary files; the API waited on them, ran out of connections and failed its health checks. Most calls came from the student
-- dashboard (GET /me reads the fees panel, and the dashboard's outstanding-fees card reads it again). No release was made that day.
--
-- What is changed here (the API keeps both reads per student for two minutes in the same release):
--   1. finance.due_for_semester asked admissions.pg_fee_stages_of (V651) for EVERY student — an undergraduate too — and the
--      postgraduate stage reader (pg_stages_of → pg_stages_read: the student's cycles, the stages recorded, the cancelled sessions) ran for
--      each call whatever the student was; it returns nothing for anyone who is not a postgraduate (its own first step keeps only
--      people.is_postgraduate students). It is now asked with the student only when the student is a postgraduate, and with no student
--      otherwise, which it answers at once (pg_stages_of returns before reading anything). The charge is the same for every student:
--      the stage and category it reads are those of a postgraduate, and nobody else ever had one.
--   2. Both functions, and the postgraduate stage readers, run with jit = off (V652, V663, V782): the database is PostgreSQL 17 with JIT
--      on, and a statement whose estimate crosses jit_above_cost is compiled on every call, a cost that does not follow the work.
-- Nothing else changes: no table, no result, no other function.
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V785: the dashboard''s fee reads made light again', true);

DO $v785$
DECLARE d text; a text; b text;
BEGIN
    d := pg_get_functiondef('finance.due_for_semester(uuid,text,integer)'::regprocedure);
    a := $a$LEFT JOIN LATERAL (SELECT x.stage_code, x.category FROM admissions.pg_fee_stages_of(p_session, ARRAY[s.id]) x) pgs ON true$a$;
    IF (length(d) - length(replace(d, a, ''))) / length(a) <> 1 THEN
        RAISE EXCEPTION 'V785: finance.due_for_semester is not as V651 left it (its postgraduate stage join is not there exactly once)';
    END IF;
    b := $b$LEFT JOIN ref.programme pgp ON pgp.code = s.programme_code   -- V785: the stage reader is asked only for a postgraduate
          LEFT JOIN LATERAL (SELECT x.stage_code, x.category
                               FROM admissions.pg_fee_stages_of(p_session,
                                        CASE WHEN people.is_postgraduate(s.entry_mode, pgp.category) THEN ARRAY[s.id] ELSE '{}'::uuid[] END) x) pgs ON true$b$;
    d := replace(d, a, b);
    EXECUTE d;
END $v785$;

ALTER FUNCTION finance.due_for_semester(uuid, text, integer) SET jit = off;
ALTER FUNCTION finance.spillover_panel(uuid, text) SET jit = off;
ALTER FUNCTION admissions.pg_fee_stages_of(text, uuid[]) SET jit = off;
ALTER FUNCTION admissions.pg_stages_of(text, uuid[]) SET jit = off;

COMMENT ON FUNCTION finance.due_for_semester(uuid, text, integer) IS
  'The cumulative school-fee charge of a student up to and including a semester (whole-session items always count). V785: the postgraduate stage reader is asked only for a postgraduate student; jit = off.';

COMMIT;
