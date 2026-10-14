-- ═══════════════════════════════════════
-- V451 — Charged as another faculty, by a standing rule; and the students with no fee stated, watched
--
--   1 · "Charged as". Communication and Media Studies (CM) is charged as Social Sciences (SS), and Technology and Industrial
--       Studies (TI) as Education (ED), by the University's word (V448, V450). Those two migrations copied the lines for the
--       sessions that stood, so each later session's upload had to state CM and TI again; a structure that left them out left
--       some 4,700 students with no fee to pay, as it did in 2025/2026. The rule is now a row: finance.faculty_fee_source says
--       which faculty a faculty's undergraduate (full-time) students are charged as, from which session. Every function that
--       matches a fee line to a student reads it (finance.fee_sources): while the faculty has no full-time FEE line of its
--       own in a session, the source faculty's faculty-wide lines reach its students, by the same level, entry mode,
--       indigeneship, spillover and semester rules. Once the Bursary states the faculty's own lines for a session, they
--       alone apply and the rule waits. A rule never chains (the source of a rule is never itself charged as another), never
--       reaches a CCE or postgraduate student (their schedules are the Centre's and the School's), and is set or ended on the
--       Fee Schedule screen by the Bursary. The five matchers are restated from V391 with that change, and the four that read
--       one student read their one-row student CTE once (MATERIALIZED): inlined, its scalar expressions (the final level, now
--       the rule) ran once per fee line; read once, a student's charges came about eight times faster on live-shaped data, the
--       same answers for every student but those the rule reaches. The lines V448 and V450 copied stay, and stand as the
--       faculties' own until an upload replaces the session's structure.
--   2 · The watch. finance.fee_gaps(session) lists the live undergraduate (full-time) students with no fee stated for a
--       session — no FEE line at all, or none for a semester that is open — grouped by programme, level, entry mode,
--       indigeneship and spillover, with the counts, read set-based in one statement over the alike groups (about a second on
--       live-shaped data). The Fee Schedule screen and Go-live readiness show it; finance.watch_fee_gaps tells the Bursary
--       (FEE_GAPS, e-mail and portal) when a group appears in the current session while a semester is open — once per new
--       group, so fixing a gap does not tell anyone again; and finance.fee_unstated_semesters tells a student which open
--       semester's fees are not yet stated for them, so the fees page says so instead of reading as settled.
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V451: charged as another faculty by a standing rule; the students with no fee stated watched', true);

-- ── 1 · the rule ────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE TABLE finance.faculty_fee_source (
    faculty_code         text PRIMARY KEY REFERENCES ref.faculty (code),
    source_faculty_code  text NOT NULL REFERENCES ref.faculty (code),
    from_session         text NULL,
    note                 text NULL,
    set_by               uuid NULL,
    set_office           text NULL,
    set_at               timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT faculty_fee_source_not_itself CHECK (faculty_code <> source_faculty_code)
);
COMMENT ON TABLE finance.faculty_fee_source IS
  'V451: the faculty whose fee lines a faculty''s undergraduate (full-time) students are charged as, from a session (NULL: every '
  'session), while the faculty has no full-time FEE line of its own in the session (finance.fee_sources). Never a chain.';
SELECT audit.attach('finance.faculty_fee_source');

-- a rule never chains: the source is never itself charged as another, and a faculty other faculties follow is never charged as another
CREATE FUNCTION finance.faculty_fee_source_guard() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_this text; v_src text; v_its text; v_followers text;
BEGIN
    v_this := (SELECT replace(replace(initcap(lower(f.name)), ' And ', ' and '), ' Of ', ' of ') FROM ref.faculty f WHERE f.code = NEW.faculty_code);
    v_src := (SELECT replace(replace(initcap(lower(f.name)), ' And ', ' and '), ' Of ', ' of ') FROM ref.faculty f WHERE f.code = NEW.source_faculty_code);
    v_its := (SELECT replace(replace(initcap(lower(f.name)), ' And ', ' and '), ' Of ', ' of ')
                FROM finance.faculty_fee_source r JOIN ref.faculty f ON f.code = r.source_faculty_code WHERE r.faculty_code = NEW.source_faculty_code);
    IF v_its IS NOT NULL THEN
        RAISE EXCEPTION 'FEE_SOURCE_CHAIN: % is itself charged as %; name % instead', v_src, v_its, v_its USING ERRCODE = '23514';
    END IF;
    v_followers := (SELECT string_agg(replace(replace(initcap(lower(f.name)), ' And ', ' and '), ' Of ', ' of '), ', ' ORDER BY f.name)
                      FROM finance.faculty_fee_source r JOIN ref.faculty f ON f.code = r.faculty_code
                     WHERE r.source_faculty_code = NEW.faculty_code AND r.faculty_code <> NEW.faculty_code);
    IF v_followers IS NOT NULL THEN
        RAISE EXCEPTION 'FEE_SOURCE_CHAIN: % is charged as %, so % cannot itself be charged as another faculty', v_followers, v_this, v_this USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER trg_faculty_fee_source_guard BEFORE INSERT OR UPDATE ON finance.faculty_fee_source
    FOR EACH ROW EXECUTE FUNCTION finance.faculty_fee_source_guard();

-- the faculty a faculty is charged as in a session: its rule, from that session on, while the faculty has no full-time FEE
-- line of its own in it (a line naming the faculty or one of its programmes; CCE and postgraduate lines are not its full-time
-- lines). A faculty with no rule — every faculty but those named — is answered by one key lookup, before the lines are read.
CREATE FUNCTION finance.fee_source_of(p_faculty text, p_session text)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT r.source_faculty_code
      FROM finance.faculty_fee_source r
     WHERE r.faculty_code = p_faculty
       AND (r.from_session IS NULL OR p_session >= r.from_session)
       AND NOT EXISTS (
           SELECT 1
             FROM finance.fee_schedule f
             LEFT JOIN ref.programme pp ON pp.code = f.programme_code
             LEFT JOIN ref.fee_group g ON g.code = f.fee_group
            WHERE f.session = p_session AND f.ended_at IS NULL AND f.kind = 'FEE'
              AND (f.faculty_code = r.faculty_code OR pp.faculty_code = r.faculty_code)
              AND f.entry_mode IS DISTINCT FROM 'CCE'
              AND NOT coalesce(f.entry_mode = 'POSTGRADUATE' OR f.level >= 700 OR pp.category = 'POST GRADUATE' OR g.applies_category = 'POST GRADUATE', false))
$fn$;
COMMENT ON FUNCTION finance.fee_source_of(text, text) IS
  'V451: the faculty a faculty''s undergraduate (full-time) students are charged as in a session — its rule '
  '(finance.faculty_fee_source) from that session on, while it has no full-time FEE line of its own in it; NULL otherwise.';

-- every rule in force for a session, for the matchers that read many students at once
CREATE FUNCTION finance.fee_sources(p_session text)
RETURNS TABLE (faculty_code text, source_code text) LANGUAGE sql STABLE AS $fn$
    SELECT x.faculty_code, x.source_code
      FROM (SELECT r.faculty_code, finance.fee_source_of(r.faculty_code, p_session) AS source_code FROM finance.faculty_fee_source r) x
     WHERE x.source_code IS NOT NULL
$fn$;
COMMENT ON FUNCTION finance.fee_sources(text) IS
  'V451: the "charged as" rules in force for a session (finance.fee_source_of of every faculty with a rule). Read by the bulk fee matchers.';

-- set, change or end a rule (p_source NULL ends it); the actor and office are the request's
CREATE FUNCTION finance.set_faculty_fee_source(p_faculty text, p_source text, p_from_session text, p_note text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_office text := nullif(current_setting('moaum.actor_office', true), '');
BEGIN
    IF NOT EXISTS (SELECT 1 FROM ref.faculty WHERE code = p_faculty) THEN
        RAISE EXCEPTION 'FEE_SOURCE_FACULTY: no faculty %', p_faculty USING ERRCODE = '23514';
    END IF;
    IF p_source IS NULL THEN
        DELETE FROM finance.faculty_fee_source WHERE faculty_code = p_faculty;
        RETURN;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM ref.faculty WHERE code = p_source) THEN
        RAISE EXCEPTION 'FEE_SOURCE_FACULTY: no faculty %', p_source USING ERRCODE = '23514';
    END IF;
    IF p_source = p_faculty THEN
        RAISE EXCEPTION 'FEE_SOURCE_SELF: a faculty is charged its own lines without a rule' USING ERRCODE = '23514';
    END IF;
    IF p_from_session IS NOT NULL AND NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_from_session) THEN
        RAISE EXCEPTION 'FEE_SOURCE_SESSION: % is not on the calendar', p_from_session USING ERRCODE = '23514';
    END IF;
    INSERT INTO finance.faculty_fee_source (faculty_code, source_faculty_code, from_session, note, set_by, set_office, set_at)
    VALUES (p_faculty, p_source, p_from_session, nullif(btrim(coalesce(p_note, '')), ''), v_actor, v_office, now())
    ON CONFLICT (faculty_code) DO UPDATE
       SET source_faculty_code = excluded.source_faculty_code, from_session = excluded.from_session, note = excluded.note,
           set_by = excluded.set_by, set_office = excluded.set_office, set_at = excluded.set_at;
END $$;
COMMENT ON FUNCTION finance.set_faculty_fee_source(text, text, text, text) IS
  'V451: the Bursary sets, changes or ends (p_source NULL) the faculty a faculty''s undergraduates are charged as, from a session.';

-- the University's word (V448, V450), from the current session on: CM as SS, TI as ED (where those faculties exist)
INSERT INTO finance.faculty_fee_source (faculty_code, source_faculty_code, from_session, note, set_by, set_office)
SELECT x.f, x.s, policy.university_current_session(), x.note, NULL, 'bursar'
  FROM (VALUES ('CM', 'SS', 'Communication and Media Studies is charged the Social Sciences fees (V448, 14 Oct 2026)'),
               ('TI', 'ED', 'Technology and Industrial Studies is charged the Education fees (V450, 14 Oct 2026)')) x(f, s, note)
 WHERE EXISTS (SELECT 1 FROM ref.faculty WHERE code = x.f) AND EXISTS (SELECT 1 FROM ref.faculty WHERE code = x.s)
ON CONFLICT (faculty_code) DO NOTHING;

-- ── 1 · every function that matches a fee line to a student reads the rule (restated from V391, the changes marked V451) ──
CREATE OR REPLACE FUNCTION finance.charges_of_as(p_student uuid, p_session text, p_kinds text[], p_programme text)
 RETURNS TABLE(id uuid, item text, amount numeric, ord integer)
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT home_state FROM finance.fee_setting WHERE id = 1),
    me AS MATERIALIZED (   -- V451: read once, not once per fee line
        SELECT s.id, coalesce(p_programme, s.programme_code) AS programme_code, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) AS state,
               coalesce(s.current_level > finance.final_level(coalesce(p_programme, s.programme_code)) AND s.status <> 'GRADUATED', false) AS is_spill,
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
               coalesce(s.current_level > finance.final_level(s.programme_code) AND s.status <> 'GRADUATED', false) AS is_spill,
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
       AND (f.level IS NULL OR f.level = me.current_level)
       AND ((f.entry_mode IS NULL AND me.entry_mode IS DISTINCT FROM 'CCE') OR f.entry_mode = me.entry_mode)   -- V379: a line naming no entry mode never reaches a CCE student
       AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code OR (f.faculty_code = me.src AND f.programme_code IS NULL))
       AND (f.programme_code IS NULL OR f.programme_code = me.programme_code)
       AND (f.fee_group IS NULL OR g.applies_category IS NULL OR g.applies_category = p.category)
       AND finance.pg_line(me.entry_mode = 'POSTGRADUATE' OR p.category = 'POST GRADUATE', f.entry_mode, f.level, f.programme_code, g.applies_category)   -- V391: a full-time line never reaches a postgraduate student
       AND (f.indigene IS NULL OR (f.indigene = 'INDIGENE') = (me.state = lower(home.home_state)));
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
               coalesce(s.current_level > finance.final_level(s.programme_code) AND s.status <> 'GRADUATED', false) AS is_spill,
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
CREATE OR REPLACE FUNCTION finance.fee_sums(p_session text, p_semester integer)
 RETURNS TABLE(profile_key text, due_before numeric, due_upto numeric, fee numeric, late_payment numeric, late_registration numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS (SELECT lower(home_state) AS home_state FROM finance.fee_setting WHERE id = 1),
    open_max AS (SELECT coalesce((SELECT max(sm.number) FROM policy.semester sm WHERE sm.session = p_session AND sm.state = 'OPEN'), 3) AS n),
    prof AS (SELECT x.*, fs.source_code AS src   -- V451: the faculty a profile is charged as, while a rule is in force
               FROM (SELECT DISTINCT pr.profile_key, pr.programme_code, pr.faculty_code, pr.category, pr.current_level, pr.entry_mode, pr.state, pr.is_spill
                       FROM finance.fee_profiles() pr) x
               LEFT JOIN finance.fee_sources(p_session) fs ON fs.faculty_code = x.faculty_code AND x.entry_mode IS DISTINCT FROM 'CCE' AND NOT people.is_postgraduate(x.entry_mode, x.category)),
    matched AS (
        SELECT pr.profile_key, f.kind, f.semester, f.amount
          FROM prof pr
          CROSS JOIN home
          JOIN finance.fee_schedule f ON f.session = p_session AND f.ended_at IS NULL
          LEFT JOIN ref.fee_group g ON g.code = f.fee_group
         WHERE f.spillover = pr.is_spill
           AND (pr.is_spill OR f.level IS NULL OR f.level = pr.current_level)
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

-- ── 2 · the students with no fee stated ─────────────────────────────────────────────────────────────────────────────────
-- every group of alike live undergraduate (full-time) students — programme, level, entry mode, indigeneship, spillover — with
-- no FEE line stated for the session (stated false), or none for a semester that is open (missing). The FEE lines are matched
-- by the same rules as finance.fee_sums, over every semester; a line naming no semester covers them all. A session before the
-- schedule's first (finance.schedule_from) has none, as finance.fee_stated reads it.
CREATE FUNCTION finance.fee_gaps(p_session text)
RETURNS TABLE (faculty_code text, faculty text, programme_code text, programme text, level integer, entry_mode text,
               indigene boolean, spillover boolean, students bigint, charged_as text, stated boolean, missing integer[])
LANGUAGE sql STABLE AS $fn$
    WITH home AS (SELECT lower(home_state) AS home_state FROM finance.fee_setting WHERE id = 1),
    open_sem AS (SELECT coalesce(array_agg(sm.number ORDER BY sm.number), '{}'::int[]) AS nums
                   FROM policy.semester sm WHERE sm.session = p_session AND sm.state = 'OPEN'),
    fl AS (SELECT pr.code, finance.final_level(pr.code) AS final FROM ref.programme pr),
    live AS (
        SELECT s.programme_code, p.faculty_code, p.category, s.current_level, s.entry_mode,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) = (SELECT h.home_state FROM home h) AS indigene,
               coalesce(s.current_level > fl.final, false) AS is_spill
          FROM people.student s
          JOIN ref.programme p ON p.code = s.programme_code
          JOIN fl ON fl.code = s.programme_code
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
$fn$;
COMMENT ON FUNCTION finance.fee_gaps(text) IS
  'V451: the live undergraduate (full-time) students with no fee stated for a session, by alike group (programme, level, entry '
  'mode, indigeneship, spillover): stated false — no FEE line reaches them; missing — the open semesters with no line for them. '
  'charged_as names the faculty a "charged as" rule in force reads. The same matching as finance.fee_sums, every semester.';

-- the open semesters of a session whose school fees are not stated for one student (an undergraduate; CCE and postgraduate
-- students are the Centre's and the School's): empty when nothing is stated at all (finance.fee_stated says that), when a
-- line covers the whole session, or when every open semester has its line
CREATE FUNCTION finance.fee_unstated_semesters(p_student uuid, p_session text)
RETURNS integer[] LANGUAGE sql STABLE AS $fn$
    WITH me AS (SELECT s.entry_mode, p.category FROM people.student s JOIN ref.programme p ON p.code = s.programme_code WHERE s.id = p_student),
    lines AS (SELECT f.semester FROM finance.charges_of_as(p_student, p_session, ARRAY['FEE'], NULL) c JOIN finance.fee_schedule f ON f.id = c.id)
    SELECT CASE
        WHEN NOT EXISTS (SELECT 1 FROM me) THEN '{}'::int[]
        WHEN (SELECT me.entry_mode IS NOT DISTINCT FROM 'CCE' OR people.is_postgraduate(me.entry_mode, me.category) FROM me) THEN '{}'::int[]
        WHEN p_session < coalesce(finance.schedule_from(), p_session) THEN '{}'::int[]
        WHEN NOT EXISTS (SELECT 1 FROM lines) THEN '{}'::int[]
        WHEN EXISTS (SELECT 1 FROM lines l WHERE l.semester IS NULL) THEN '{}'::int[]
        ELSE coalesce((SELECT array_agg(sm.number ORDER BY sm.number) FROM policy.semester sm
                        WHERE sm.session = p_session AND sm.state = 'OPEN'
                          AND NOT EXISTS (SELECT 1 FROM lines l WHERE l.semester = sm.number)), '{}'::int[]) END
$fn$;
COMMENT ON FUNCTION finance.fee_unstated_semesters(uuid, text) IS
  'V451: the open semesters of a session for which no school-fee line reaches an undergraduate student, while some other '
  'semester''s does — the student''s fees page says these are not yet stated rather than reading as settled.';

-- ── 2 · the watch: the Bursary told of a new group, once ────────────────────────────────────────────────────────────────
CREATE TABLE finance.fee_gap_watch (
    session     text PRIMARY KEY,
    told_keys   text[] NOT NULL DEFAULT '{}',
    told_at     timestamptz NULL,
    told        integer NOT NULL DEFAULT 0,
    students    bigint NOT NULL DEFAULT 0,
    groups      integer NOT NULL DEFAULT 0,
    checked_at  timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE finance.fee_gap_watch IS
  'V451: the fee-gap watch''s last reading of a session — the groups it last saw (told_keys), when it last told the Bursary and '
  'how many messages, the students and groups with no fee stated, when it read.';
SELECT audit.exempt('finance.fee_gap_watch', 'V451: the watch''s own reading, rewritten by the hourly job; what it told the Bursary is on the outbox');

CREATE FUNCTION finance.watch_fee_gaps(p_session text DEFAULT NULL)
RETURNS int LANGUAGE plpgsql AS $$
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
              FROM (SELECT concat_ws('|', g.programme_code, g.level, g.entry_mode, g.indigene, g.spillover, coalesce(g.missing::text, 'none')) AS k FROM g) x),
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
                  WHERE a.office_code = 'bursar' AND pe.ended_on IS NULL
                    AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date) LOOP
            told := told + platform.tell_person(p.person_id, 'FEE_GAPS', NULL, v_vars,
                                                'fee-gaps:' || v_ses || ':' || md5(array_to_string(v_new, ',')) || ':' || v_at, ARRAY['EMAIL', 'PORTAL']);
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
END $$;
COMMENT ON FUNCTION finance.watch_fee_gaps(text) IS
  'V451: while a semester of the session (the current one by default) is open, reads finance.fee_gaps and tells every Bursary office holder '
  '(FEE_GAPS, e-mail and portal) when a group appears that it had not seen at its last reading. Returns the messages queued.';

INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('FEE_GAPS', 'Students with no fee stated',
 'To the Bursary when live undergraduate students of the current session have no school fee stated for it, or none for an open semester, while a semester is open; once per new group of alike students',
 '[STUDENTS] students have no school fee stated for [SESSION]',
 E'Dear [FIRST_NAME],\n\n[STUDENTS] undergraduate students of [SESSION] have no school fee stated for them, or none for a semester that is open, so the portal shows them nothing to pay for it and they cannot register for that semester. By faculty: [FACULTIES].\n\nThe students are listed by programme, level and entry mode on the Fee Schedule screen. State their lines there, or name the faculty they are charged as.\n\n[PORTAL_URL]\n\n[UNIVERSITY_SHORT]',
 '[UNIVERSITY_SHORT] portal: [STUDENTS] students have no school fee stated for [SESSION]. See the Fee Schedule screen.',
 '[STUDENTS] students have no school fee stated for [SESSION]',
 'By faculty: [FACULTIES]. They are listed on the Fee Schedule screen; state their lines there, or name the faculty they are charged as.',
 ARRAY['FIRST_NAME','SESSION','STUDENTS','GROUPS','NEW_GROUPS','FACULTIES','PORTAL_URL','UNIVERSITY_SHORT'], true, 'HIGH');

COMMIT;
