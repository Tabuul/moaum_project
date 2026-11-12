-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V725 · A session's level counts the merged session once — on receipts, results, the historical fees and the payments view
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's word of 11 November 2026: the receipt of BSU/AR/REL/19/52222 (entered 2019/2020) for the first semester of
--  2022/2023 printed 400 Level; it is 300 Level — 2019/2020 was merged into 2020/2021 (V661), "so even students that were admitted
--  before the time the sessions were merged were affected".
--  The cohort engine (people.academic_position, V331, V661) counts a student's sessions as policy.sessions_elapsed from
--  policy.effective_session(entry): the cancelled 2019/2020 is not a year of study, for its own entrants and for every earlier cohort.
--  Four readers counted otherwise, each when the session holds no registration or enrolment of the student — most old-portal
--  students' past sessions:
--    · people.receipt_level (V672, V696) — every receipt: the student's, the Student 360°'s, ICT Support's and the public verify
--      page's — counted the calendar years since entry: a /19/ student read 200 … 600 for 2020/2021 … 2024/2025, earlier cohorts one
--      level high too;
--    · people.level_in (V330, V455, V696) — results statements, the results verify page, payment reallocation — counted the
--      calendar's rows between entry and the session, the cancelled one among them, and for an entry before the calendar's first
--      session (live's starts at 2019/2020) nothing at all: it fell to the record's level, often a stale 100;
--    · finance.historical_rows_read (V720, V723) — the past-session fee account, its fee lines and its spillover year — counted the
--      calendar's index the same way;
--    · reporting.level_in_session (V279) — the payments view's level — counted the calendar years.
--  The levels stored are not wrong: old-portal registrations and enrolments agree with the merged count (none of 2,614 on a copy of
--  live is a level high), and a receipt stores no level — every receipt, printed or verified, reads right at once.
--  One count everywhere: people.counted_sessions(entry, session) = policy.sessions_elapsed of the two sessions' effective sessions, a
--  malformed session name ('2022/2024') read as the session starting in its first year. The set readers never count once a row: the
--  historical engine once a pair of entry session and session, the payments view from the cancelled years read once a query. The
--  session roll-over's promotion ceiling, the College's minimum years and the programme's timeline count the same way. A merger (or
--  its undoing) marks the historical summaries stale; the students whose count changes here are marked once.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'registrar', true),
       set_config('moaum.reason', 'V725: a session''s level counts the merged session once (the University''s word of 11 November 2026)', true);

-- ── 1 · one count of the sessions studied ─────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION policy.session_normal(p_session text) RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN p_session ~ '^[0-9]{4}'
                     AND NOT (p_session ~ '^[0-9]{4}/[0-9]{4}$' AND substr(p_session, 6, 4)::int = left(p_session, 4)::int + 1)
                THEN left(p_session, 4) || '/' || (left(p_session, 4)::int + 1) ELSE p_session END
$$;
COMMENT ON FUNCTION policy.session_normal(text) IS
  'V725: a session name as the calendar writes it — one that starts with a year but is not written as the calendar writes it (''2022/2024'', ''2022/23'', ''2022'': old-portal records) read as the session starting in that year, as the payments view reads it.';

CREATE OR REPLACE FUNCTION people.counted_sessions(p_entry_session text, p_session text) RETURNS integer LANGUAGE sql STABLE AS $$
    SELECT policy.sessions_elapsed(policy.effective_session(policy.session_normal(p_entry_session)),
                                   policy.effective_session(policy.session_normal(p_session)))
$$;
COMMENT ON FUNCTION people.counted_sessions(text, text) IS
  'V725: the sessions studied from an entry session to a session, as the cohort engine counts them — from the effective (merged-into) entry, a cancelled session not counted, an entry before the calendar''s first session counted by its year; NULL when either is not a session. A level is entry_level + 100 × this.';

-- the cancelled sessions' years and the years they were merged into, read once a query by the set readers (ordered by year)
CREATE OR REPLACE FUNCTION policy.cancelled_years(OUT years integer[], OUT into_years integer[]) RETURNS record LANGUAGE sql STABLE AS $$
    SELECT coalesce(array_agg(policy.session_year(a.name) ORDER BY policy.session_year(a.name)), '{}'::integer[]),
           coalesce(array_agg(policy.session_year(policy.effective_session(a.name)) ORDER BY policy.session_year(a.name)), '{}'::integer[])
      FROM policy.academic_session a WHERE a.state = 'CANCELLED' AND policy.session_year(a.name) IS NOT NULL
$$;
COMMENT ON FUNCTION policy.cancelled_years() IS
  'V725: the cancelled sessions'' years, ascending, and the year of the session each was merged into at the end of its chain (policy.effective_session: 2019/2020 into 2020/2021 into 2021/2022 gives 2021) — what reporting.level_in_session needs to count the sessions studied without reading the calendar once a row.';

-- ── 2 · the readers of one student's level ────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION people.receipt_level(p_student uuid, p_session text)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE WHEN c.cap IS NULL THEN x.lvl ELSE least(c.cap, x.lvl) END
      FROM (SELECT greatest(
                people.record_level_in(p_student, p_session),
                coalesce(
                    (SELECT r.level FROM registration.course_registration r WHERE r.student_id = p_student AND r.session = p_session
                      ORDER BY (r.status IN ('APPROVED', 'LOCKED')) DESC, r.semester LIMIT 1),
                    (SELECT e.level FROM people.enrolment e WHERE e.student_id = p_student AND e.session = p_session LIMIT 1),
                    -- V725: the sessions studied counted as the cohort engine counts them, a merged session once (V455: a postgraduate's
                    -- level is their own)
                    (SELECT CASE WHEN NOT people.is_postgraduate(st.entry_mode, p.category) AND n.n IS NOT NULL
                                 THEN least(600, greatest(100, st.entry_level + 100 * n.n))
                                 ELSE st.current_level END
                       FROM people.student st LEFT JOIN ref.programme p ON p.code = st.programme_code
                       CROSS JOIN LATERAL (SELECT people.counted_sessions(st.entry_session, p_session) AS n) n
                      WHERE st.id = p_student))) AS lvl) x
      CROSS JOIN LATERAL (SELECT people.cohort_cap(p_student, p_session) AS cap) c
$function$;
COMMENT ON FUNCTION people.receipt_level(uuid, text) IS
  'V672, V696, V725: the level a receipt prints for a session — the record''s level in the current session, never below; else the session''s registration, its enrolment, or the sessions studied since entry as the cohort engine counts them (a merged session once); a cohort override''s cap from the current session on.';

CREATE OR REPLACE FUNCTION people.level_in(p_student uuid, p_session text, p_semester integer DEFAULT NULL::integer)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    SELECT CASE WHEN c.cap IS NULL THEN x.lvl ELSE least(c.cap, x.lvl) END
      FROM (SELECT coalesce(
                (SELECT r.level FROM registration.course_registration r
                  WHERE r.student_id = p_student AND r.session = p_session AND (p_semester IS NULL OR r.semester = p_semester)
                  ORDER BY (r.status IN ('APPROVED','LOCKED')) DESC, r.semester LIMIT 1),
                (SELECT r.level FROM registration.course_registration r
                  WHERE r.student_id = p_student AND r.session = p_session
                  ORDER BY (r.status IN ('APPROVED','LOCKED')) DESC, r.semester LIMIT 1),
                (SELECT e.level FROM people.enrolment e WHERE e.student_id = p_student AND e.session = p_session),
                (SELECT CASE WHEN people.is_postgraduate(st.entry_mode, pp.category) THEN st.current_level   -- V455: a postgraduate's level is their own
                             -- V725: the sessions studied as the cohort engine counts them — a merged session once, an entry before
                             -- the calendar's first session by its year — not the calendar's rows
                             WHEN n.n >= 0 THEN least(600, st.entry_level + 100 * n.n)
                        END
                   FROM people.student st
                   LEFT JOIN ref.programme pp ON pp.code = st.programme_code
                   CROSS JOIN LATERAL (SELECT people.counted_sessions(st.entry_session, p_session) AS n) n
                  WHERE st.id = p_student),
                (SELECT st.current_level FROM people.student st WHERE st.id = p_student)) AS lvl) x
      CROSS JOIN LATERAL (SELECT people.cohort_cap(p_student, p_session) AS cap) c
$function$;
COMMENT ON FUNCTION people.level_in(uuid, text, integer) IS
  'V330, V455, V696, V725: the level of a student in a session (and semester) — the registration, else the enrolment, else the sessions studied since entry as the cohort engine counts them (a merged session once), else the record; a postgraduate''s own level; a cohort override''s cap from the current session on.';

CREATE OR REPLACE FUNCTION people.cohort_cap(p_student uuid, p_session text)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    SELECT least(600, greatest(st.entry_level, st.entry_level + 100 * people.counted_sessions(o.effective_cohort, p_session)))   -- V725
      FROM people.cohort_override o
      JOIN people.student st ON st.id = o.student_id
      LEFT JOIN ref.programme p ON p.code = st.programme_code
     WHERE o.student_id = p_student
       AND p_session ~ '^[0-9]{4}/[0-9]{4}$' AND o.effective_cohort ~ '^[0-9]{4}/[0-9]{4}$' AND st.entry_level IS NOT NULL
       AND NOT people.is_postgraduate(st.entry_mode, p.category) AND st.entry_mode IS DISTINCT FROM 'CCE'
       AND left(p_session, 4)::int >= coalesce(left(coalesce(people.student_current_session(st.id), policy.university_current_session()), 4)::int, 0)
$function$;

-- the level in a session for the set readers: the 7-argument form counts from the cancelled years given (joined once a query: the
-- payments view, the old-fees reconciliation, the overpaid list; read once a call: the old-fees import); the 5-argument form, for a
-- caller reading one value, reads them itself (it is not inlined, so no set reader calls it once a row)
CREATE OR REPLACE FUNCTION reporting.level_in_session(p_entry_level integer, p_entry_session text, p_current_level integer, p_entry_mode text,
                                                      p_session text, p_years integer[], p_into integer[])
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
    SELECT CASE WHEN p_entry_mode = 'POSTGRADUATE' OR p_session IS NULL OR p_entry_session IS NULL
                     OR p_session !~ '^[0-9]{4}' OR p_entry_session !~ '^[0-9]{4}' THEN p_current_level
                ELSE least(600, greatest(100, coalesce(p_entry_level, 100) + 100 * (
                       (coalesce(p_into[array_position(p_years, left(p_session, 4)::int)], left(p_session, 4)::int)
                          - width_bucket(coalesce(p_into[array_position(p_years, left(p_session, 4)::int)], left(p_session, 4)::int), p_years))
                     - (coalesce(p_into[array_position(p_years, left(p_entry_session, 4)::int)], left(p_entry_session, 4)::int)
                          - width_bucket(coalesce(p_into[array_position(p_years, left(p_entry_session, 4)::int)], left(p_entry_session, 4)::int), p_years)))))
           END
$function$;
COMMENT ON FUNCTION reporting.level_in_session(integer, text, integer, text, text, integer[], integer[]) IS
  'V725: a student''s level in a session by the sessions studied since entry — each year taken to the year it was merged into, the cancelled years before it taken off (width_bucket over the ascending cancelled years) — equal to people.counted_sessions; the cancelled years given from policy.cancelled_years(), read once a query.';

CREATE OR REPLACE FUNCTION reporting.level_in_session(p_entry_level integer, p_entry_session text, p_current_level integer, p_entry_mode text, p_session text)
 RETURNS integer
 LANGUAGE sql
 STABLE
AS $function$
    SELECT reporting.level_in_session(p_entry_level, p_entry_session, p_current_level, p_entry_mode, p_session, c.years, c.into_years)
      FROM policy.cancelled_years() c
$function$;
COMMENT ON FUNCTION reporting.level_in_session(integer, text, integer, text, text) IS
  'V279, V725: a student''s level in a session by the sessions studied since entry, a merged session once (the cancelled years read here; a set reader passes them to the 7-argument form instead).';

-- ── 3 · the historical fee engine: a period's level counted as the cohort engine counts it ─────────────────────────────────
CREATE OR REPLACE FUNCTION finance.historical_rows_read(p_students uuid[])
 RETURNS TABLE(student_id uuid, session text, semester integer, level integer, programme_code text, assessed numeric, source text, source_ref text, assessment_id uuid, structure_amount numeric, structure_lines integer, pending_id uuid, pending_ref text, pending_amount numeric, paid numeric, outstanding numeric, credit numeric, status text, waived numeric)
 LANGUAGE sql
 STABLE
AS $function$
    WITH home AS MATERIALIZED (SELECT lower(home_state) AS home_state FROM finance.fee_setting WHERE id = 1),
    -- V720: a student's past ends before the current session of THEIR calendar — the University's, the School of Postgraduate
    -- Studies' for a postgraduate student, the Centre's for a CCE student — as people.student_current_session reads it
    bounds AS MATERIALIZED (SELECT finance.historical_start() AS start,
                                   finance.session_before(policy.university_current_session()) AS before_current,
                                   finance.session_before(coalesce((SELECT a.name FROM admissions.pg_academic_session a WHERE a.state = 'CURRENT' ORDER BY a.name DESC LIMIT 1),
                                                            policy.university_current_session())) AS before_pg,   -- V723: the School's own row, else the University's session
                                                                                                                   -- (never admissions.pg_current_session's literal fallback)
                                   finance.session_before(coalesce(policy.route_session('CCE'), policy.university_current_session())) AS before_cce),
    -- the calendar's sessions, their state and semesters (V725: a period's level is no longer counted from the calendar's rows)
    cal AS MATERIALIZED (SELECT a.name, a.state, a.semesters FROM policy.academic_session a),
    st AS MATERIALIZED (
        SELECT s.id, s.programme_code, p.faculty_code, p.category, s.entry_mode, s.entry_session, s.entry_level, s.current_level,
               people.is_postgraduate(s.entry_mode, p.category) AS pg,
               lower(btrim(coalesce(s.state_of_origin, r.state_of_origin, ''))) = (SELECT h.home_state FROM home h) AS indigene,
               greatest(s.entry_session, b.start) AS first_session,
               CASE WHEN s.status = 'GRADUATED' OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED')
                    THEN records.graduation_session(s.id)
                    -- V723: a student studying (ACTIVE, PROBATION), deferred or suspended is bounded by their calendar; one who has left —
                    -- withdrawn, expelled, transferred out, rusticated, dormant, deceased — or admitted and never come, by the last session
                    -- they enrolled or registered in (as records.graduation_session falls back), never past the calendar's bound; none: no past
                    WHEN s.status IN ('ACTIVE', 'PROBATION', 'DEFERRED', 'SUSPENDED')
                    THEN CASE WHEN s.entry_mode = 'CCE' THEN b.before_cce WHEN s.entry_mode = 'POSTGRADUATE' THEN b.before_pg ELSE b.before_current END
                    ELSE (SELECT CASE WHEN max(x.session) IS NULL THEN NULL ELSE least(max(x.session), CASE WHEN s.entry_mode = 'CCE' THEN b.before_cce WHEN s.entry_mode = 'POSTGRADUATE' THEN b.before_pg ELSE b.before_current END) END
                            FROM (SELECT e.session FROM people.enrolment e WHERE e.student_id = s.id
                                  UNION ALL
                                  SELECT r.session FROM registration.course_registration r
                                   WHERE r.student_id = s.id AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) x) END AS last_session
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
        SELECT st.*, fl.final_level, a.name AS session, sm.n AS semester
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
    -- V725: the sessions studied from entry to each period as the cohort engine counts them — a merged (cancelled) session once, an
    -- entry before the calendar's first session by its year — worked out once a pair of entry session and session, never once a row
    coh AS MATERIALIZED (SELECT d.entry_session, d.session, people.counted_sessions(d.entry_session, d.session) AS n
                           FROM (SELECT DISTINCT p0.entry_session, p0.session FROM per0 p0 WHERE NOT p0.pg) d),
    per AS MATERIALIZED (
        SELECT p0.*, coalesce(rs.level, rx.level, en.level,
                              CASE WHEN p0.pg THEN p0.current_level
                                   WHEN ch.n >= 0 THEN least(600, p0.entry_level + 100 * ch.n) END,
                              p0.current_level) AS level
          FROM per0 p0
          LEFT JOIN coh ch ON ch.entry_session = p0.entry_session AND ch.session = p0.session
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

-- ── 4 · the session roll-over's promotion ceiling, the College's minimum years, the programme's timeline ───────────────────
CREATE OR REPLACE FUNCTION people.roll_over_session(p_to_session text, p_confirm text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE who uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_created boolean := false; v_promoted int := 0; v_held int := 0; v_to int; r record;
BEGIN
    IF who IS NULL THEN
        RAISE EXCEPTION 'a session roll-over is made by a person' USING ERRCODE = '23514';
    END IF;
    IF upper(btrim(coalesce(p_confirm, ''))) <> 'ROLLOVER' THEN
        RAISE EXCEPTION 'type ROLLOVER to confirm promoting continuing students into %', p_to_session USING ERRCODE = '23514';
    END IF;
    IF coalesce(btrim(p_reason), '') = '' THEN
        RAISE EXCEPTION 'a session roll-over names its reason' USING ERRCODE = '23514';
    END IF;
    v_to := policy.session_year(p_to_session);
    IF v_to IS NULL THEN
        RAISE EXCEPTION 'a session is named YYYY/YYYY, not %', p_to_session USING ERRCODE = '23514';
    END IF;
    -- V702: the levels set here are the target session's (a student held after a change of department is held in it)
    PERFORM set_config('moaum.level_session', p_to_session, true);

    -- open the target session (and its two semesters) if it is not there yet, as PLANNED
    IF NOT EXISTS (SELECT 1 FROM policy.academic_session WHERE name = p_to_session) THEN
        PERFORM assessment.ensure_session(p_to_session);
        UPDATE policy.academic_session SET state = 'PLANNED' WHERE name = p_to_session;
        v_created := true;
    END IF;

    -- V641: a student enters a session at their entry level — never promoted into their entry session (or one before it), nor
    -- past the level the entry reaches by the target session; counted, before anyone moves
    SELECT count(*) INTO v_held
      FROM people.student s
      LEFT JOIN (SELECT d.entry_session, people.counted_sessions(d.entry_session, p_to_session) AS n FROM (SELECT DISTINCT x.entry_session FROM people.student x) d) cn ON cn.entry_session = s.entry_session   -- V725
     WHERE s.status IN ('ACTIVE', 'PROBATION')
       AND s.matric_no IS NOT NULL
       AND s.current_level < coalesce(finance.final_level(s.programme_code), 400)
       AND NOT EXISTS (SELECT 1 FROM people.enrolment e WHERE e.student_id = s.id AND e.session = p_to_session)
       AND NOT coalesce(cn.n > 0
                        AND s.current_level + 100 <= s.entry_level + 100 * cn.n
                        AND s.current_level + 100 <= coalesce(people.department_hold_of(s.id, p_to_session), 999), false);   -- V702

    FOR r IN
        SELECT s.id, s.current_level + 100 AS new_level
          FROM people.student s
          LEFT JOIN (SELECT d.entry_session, people.counted_sessions(d.entry_session, p_to_session) AS n FROM (SELECT DISTINCT x.entry_session FROM people.student x) d) cn ON cn.entry_session = s.entry_session   -- V725
         WHERE s.status IN ('ACTIVE', 'PROBATION')
           AND s.matric_no IS NOT NULL
           AND s.current_level < coalesce(finance.final_level(s.programme_code), 400)
           AND NOT EXISTS (SELECT 1 FROM people.enrolment e WHERE e.student_id = s.id AND e.session = p_to_session)
           AND cn.n > 0
           AND s.current_level + 100 <= s.entry_level + 100 * cn.n
           AND s.current_level + 100 <= coalesce(people.department_hold_of(s.id, p_to_session), 999)   -- V702: never above a hold
    LOOP
        UPDATE people.student SET current_level = r.new_level WHERE id = r.id;
        INSERT INTO people.enrolment (id, student_id, session, level)
        VALUES (gen_random_uuid(), r.id, p_to_session, r.new_level)
        ON CONFLICT (student_id, session) DO NOTHING;
        v_promoted := v_promoted + 1;
    END LOOP;

    PERFORM set_config('moaum.level_session', '', true);
    RETURN jsonb_build_object('session', p_to_session, 'created_session', v_created,
                             'promoted', v_promoted, 'held', v_held, 'reason', btrim(p_reason));
END $function$;

CREATE OR REPLACE FUNCTION college.min_years_met(p_student uuid, p_session text)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
    SELECT coalesce((people.counted_sessions(s.entry_session, p_session) + 1)   -- V725: a merged session counted once
                    >= CASE WHEN s.entry_mode = 'DIRECT_ENTRY' THEN coalesce(r.min_years_de, 5) ELSE coalesce(r.min_years_utme, 6) END, true)
      FROM people.student s LEFT JOIN college.programme_rule r ON r.programme_code = s.programme_code WHERE s.id = p_student
$function$;

CREATE OR REPLACE FUNCTION people.programme_timeline(p_student uuid)
 RETURNS TABLE(entry_session text, entry_level integer, final_level integer, semesters_per_session integer, original_semesters integer, original_completion_session text, original_completion_semester integer, original_completion_on date, approved_semesters integer, approved_sessions numeric, approved_count integer, adjusted_semesters integer, adjusted_completion_session text, adjusted_completion_semester integer, adjusted_completion_on date, live_state text, live_return_session text, live_return_semester integer, live_return_on date)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s people.student; v_final int; v_sps int; v_years int; v_orig int; v_ext int := 0; v_n int := 0; v_idx int; live people.deferment;
BEGIN
    SELECT * INTO s FROM people.student WHERE id = p_student;
    IF s.id IS NULL THEN RETURN; END IF;
    v_final := coalesce(finance.final_level(s.programme_code), 400);
    v_sps := coalesce((SELECT a.semesters FROM policy.academic_session a WHERE a.name = s.entry_session), 2);
    v_years := greatest((v_final - coalesce(s.entry_level, 100)) / 100 + 1, 1);
    -- V381: a CCE student's programme runs the CCE duration (six years unless the Academic Office stated another)
    IF s.entry_mode = 'CCE' THEN
        SELECT coalesce(t.final_level, v_final), coalesce(t.duration_years, v_years) INTO v_final, v_years FROM ref.programme_route_terms(s.programme_code, 'CCE') t;
    END IF;
    v_orig := v_years * v_sps;
    SELECT coalesce(sum(coalesce(d.extension_semesters, people.deferment_semesters(d.kind, d.session))), 0), count(*)
      INTO v_ext, v_n
      FROM people.deferment d WHERE d.student_id = p_student AND d.state IN ('APPROVED','ACTIVE','COMPLETED');
    SELECT * INTO live FROM people.deferment d WHERE d.student_id = p_student AND d.state IN ('APPROVED','ACTIVE') ORDER BY d.return_on DESC NULLS LAST LIMIT 1;
    v_idx := v_orig + v_ext - 1;   -- zero-based index of the last semester, counted from the entry session's first
    RETURN QUERY SELECT s.entry_session, s.entry_level, v_final, v_sps,
        v_orig, policy.session_after(policy.effective_session(policy.session_normal(s.entry_session)), v_years - 1), v_sps, people.period_end(p_student, policy.session_after(policy.effective_session(policy.session_normal(s.entry_session)), v_years - 1), v_sps),
        v_ext, round(v_ext::numeric / v_sps, 1), v_n,
        v_orig + v_ext, policy.session_after(policy.effective_session(policy.session_normal(s.entry_session)), v_idx / v_sps), (v_idx % v_sps) + 1, people.period_end(p_student, policy.session_after(policy.effective_session(policy.session_normal(s.entry_session)), v_idx / v_sps), (v_idx % v_sps) + 1),
        live.state, live.return_session, live.return_semester, live.return_on;
END $function$;

-- ── 5 · the payments view (the Payments screen, analytics, the query engine), the old-fees reconciliation, the overpaid list, the old-fees import
CREATE OR REPLACE VIEW reporting.payments AS
 SELECT 'STUDENT'::text AS source,
    r.id AS payment_id,
    r.reference,
    r.receipt_no,
    r.purpose,
    NULL::text AS kind,
    k.code AS category_code,
    r.amount,
    r.generated_at,
    r.confirmed_at,
    r.expires_at,
    r.channel,
    r.session,
    st.id AS student_id,
    NULL::uuid AS application_id,
    NULL::uuid AS pg_application_id,
    st.id::text AS payer_key,
    st.surname,
    st.other_names,
    COALESCE(st.matric_no, st.admission_no) AS number,
    st.sex,
    st.entry_mode,
    st.entry_session,
    st.status,
    f.code AS faculty_code,
    f.name AS faculty,
    d.code AS dept_code,
    d.name AS department,
    p.code AS programme_code,
    p.name AS programme,
    reporting.level_in_session(st.entry_level, st.entry_session, st.current_level, st.entry_mode, r.session, cy.years, cy.into_years) AS level,
    st.entry_mode = 'POSTGRADUATE'::text OR p.category = 'POST GRADUATE'::text AS is_pg,
    COALESCE(f.college_code, ''::text) = 'CHS'::text AS is_chs,
    pt.code AS programme_type,
    finance.admission_route_of(st.entry_mode) AS admission_route,
    st.study_mode,
    COALESCE(cat.purpose, 'OTHER'::text) AS purpose_code,
    own.source_module,
    own.responsible_office,
        CASE
            WHEN r.purpose ~* '(first|1st) semester'::text THEN 1
            WHEN r.purpose ~* '(second|2nd) semester'::text THEN 2
            ELSE NULL::integer
        END AS semester,
    st.jamb_reg_no,
    NULL::text AS application_no,
    NULL::text AS exam_no,
    NULL::uuid AS jupeb_application_id,
        CASE
            WHEN r.confirmed_at IS NOT NULL THEN 'PAID'::text
            WHEN r.expires_at <= now() THEN 'EXPIRED'::text
            ELSE 'PENDING'::text
        END AS ledger_status
   FROM finance.payment_reference r
     JOIN people.student st ON st.id = r.student_id
     JOIN ref.programme p ON p.code = st.programme_code
     JOIN ref.faculty f ON f.code = p.faculty_code
     JOIN ref.department d ON d.code = p.dept_code
     CROSS JOIN policy.cancelled_years() cy(years, into_years)
     LEFT JOIN finance.category_memo km ON km.kind = ''::text AND km.purpose = COALESCE(r.purpose, ''::text)
     CROSS JOIN LATERAL ( SELECT COALESCE(km.code, finance.categorise(NULL::text, r.purpose)) AS code) k
     LEFT JOIN finance.payment_category cat ON cat.code = k.code
     LEFT JOIN finance.programme_type_memo ptm ON ptm.entry_mode = COALESCE(st.entry_mode, ''::text) AND ptm.category = COALESCE(p.category, ''::text)
     CROSS JOIN LATERAL ( SELECT COALESCE(ptm.code, finance.programme_type_for(st.entry_mode, p.category)) AS code) pt
     LEFT JOIN finance.owner_memo om ON om.purpose = COALESCE(cat.purpose, 'OTHER'::text) AND om.programme_type = pt.code
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN om.purpose IS NOT NULL THEN om.source_module
                    ELSE ( SELECT o.source_module
                       FROM finance.payment_owner(COALESCE(cat.purpose, 'OTHER'::text), pt.code) o(source_module, responsible_office))
                END AS source_module,
                CASE
                    WHEN om.purpose IS NOT NULL THEN om.responsible_office
                    ELSE ( SELECT o.responsible_office
                       FROM finance.payment_owner(COALESCE(cat.purpose, 'OTHER'::text), pt.code) o(source_module, responsible_office))
                END AS responsible_office) own
  WHERE r.archived_at IS NULL
UNION ALL
 SELECT 'APPLICANT'::text AS source,
    fr.id AS payment_id,
    fr.reference,
    fr.receipt_no,
    NULL::text AS purpose,
    fr.kind,
    k.code AS category_code,
    fr.amount,
    fr.generated_at,
    fr.confirmed_at,
    fr.expires_at,
    fr.channel,
    a.session,
    s.id AS student_id,
    a.id AS application_id,
    NULL::uuid AS pg_application_id,
    COALESCE(s.id::text, a.id::text) AS payer_key,
    c.surname,
    c.other_names,
    COALESCE(s.matric_no, s.admission_no, a.application_no) AS number,
    COALESCE(s.sex, cr.sex) AS sex,
    c.entry_mode,
    a.session AS entry_session,
    COALESCE(s.status, 'APPLICANT'::text) AS status,
    f.code AS faculty_code,
    f.name AS faculty,
    d.code AS dept_code,
    d.name AS department,
    p.code AS programme_code,
    p.name AS programme,
    c.entry_level AS level,
    false AS is_pg,
    COALESCE(f.college_code, ''::text) = 'CHS'::text AS is_chs,
    pt.code AS programme_type,
    finance.admission_route_of(c.entry_mode) AS admission_route,
        CASE
            WHEN c.entry_mode = 'CCE'::text THEN 'PART_TIME'::text
            ELSE 'FULL_TIME'::text
        END AS study_mode,
    COALESCE(cat.purpose, 'OTHER'::text) AS purpose_code,
    own.source_module,
    own.responsible_office,
    NULL::integer AS semester,
    c.jamb_reg_no,
    a.application_no,
    NULL::text AS exam_no,
    NULL::uuid AS jupeb_application_id,
        CASE
            WHEN fr.confirmed_at IS NOT NULL THEN 'PAID'::text
            WHEN fr.expires_at <= now() THEN 'EXPIRED'::text
            ELSE 'PENDING'::text
        END AS ledger_status
   FROM admissions.fee_reference fr
     JOIN admissions.application a ON a.id = fr.application_id
     JOIN admissions.candidate c ON c.id = a.candidate_id
     LEFT JOIN admissions.caps_row cr ON cr.id = c.admitted_from
     LEFT JOIN people.student s ON s.candidate_id = c.id
     LEFT JOIN ( SELECT DISTINCT ON (pn.name) pn.name,
            pn.code
           FROM ref.programme pn
          ORDER BY pn.name, pn.archived, pn.code) pnm ON pnm.name = c.programme
     LEFT JOIN ref.programme p ON p.code = pnm.code
     LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     LEFT JOIN ref.department d ON d.code = p.dept_code
     LEFT JOIN finance.category_memo km ON km.kind = COALESCE(fr.kind, ''::text) AND km.purpose = ''::text
     CROSS JOIN LATERAL ( SELECT COALESCE(km.code, finance.categorise(fr.kind, NULL::text)) AS code) k
     LEFT JOIN finance.payment_category cat ON cat.code = k.code
     LEFT JOIN finance.programme_type_memo ptm ON ptm.entry_mode = COALESCE(c.entry_mode, ''::text) AND ptm.category = COALESCE(p.category, ''::text)
     CROSS JOIN LATERAL ( SELECT COALESCE(ptm.code, finance.programme_type_for(c.entry_mode, p.category)) AS code) pt
     LEFT JOIN finance.owner_memo om ON om.purpose = COALESCE(cat.purpose, 'OTHER'::text) AND om.programme_type = pt.code
     CROSS JOIN LATERAL ( SELECT
                CASE
                    WHEN om.purpose IS NOT NULL THEN om.source_module
                    ELSE ( SELECT o.source_module
                       FROM finance.payment_owner(COALESCE(cat.purpose, 'OTHER'::text), pt.code) o(source_module, responsible_office))
                END AS source_module,
                CASE
                    WHEN om.purpose IS NOT NULL THEN om.responsible_office
                    ELSE ( SELECT o.responsible_office
                       FROM finance.payment_owner(COALESCE(cat.purpose, 'OTHER'::text), pt.code) o(source_module, responsible_office))
                END AS responsible_office) own
UNION ALL
 SELECT 'PG'::text AS source,
    fr.id AS payment_id,
    fr.reference,
    NULL::text AS receipt_no,
    NULL::text AS purpose,
    'PG_'::text || fr.kind AS kind,
    k.code AS category_code,
    fr.amount,
    fr.generated_at,
    fr.confirmed_at,
    fr.expires_at,
    fr.channel,
    pa.session,
    pa.student_id,
    NULL::uuid AS application_id,
    pa.id AS pg_application_id,
    COALESCE(pa.student_id::text, pa.id::text) AS payer_key,
    ap.surname,
    ap.other_names,
    COALESCE(s.matric_no, s.admission_no, pa.application_no) AS number,
    COALESCE(s.sex, ap.sex) AS sex,
    'POSTGRADUATE'::text AS entry_mode,
    pa.session AS entry_session,
    COALESCE(s.status, pa.state) AS status,
    f.code AS faculty_code,
    f.name AS faculty,
    d.code AS dept_code,
    d.name AS department,
    p.code AS programme_code,
    p.name AS programme,
    COALESCE(s.current_level, pa.entry_level) AS level,
    true AS is_pg,
    COALESCE(f.college_code, ''::text) = 'CHS'::text AS is_chs,
    pt.code AS programme_type,
    'POSTGRADUATE'::text AS admission_route,
    s.study_mode,
    COALESCE(cat.purpose, 'OTHER'::text) AS purpose_code,
    own.source_module,
    own.responsible_office,
    NULL::integer AS semester,
    NULL::text AS jamb_reg_no,
    pa.application_no,
    NULL::text AS exam_no,
    NULL::uuid AS jupeb_application_id,
        CASE
            WHEN fr.confirmed_at IS NOT NULL THEN 'PAID'::text
            WHEN fr.expires_at <= now() THEN 'EXPIRED'::text
            ELSE 'PENDING'::text
        END AS ledger_status
   FROM admissions.pg_fee_reference fr
     JOIN admissions.pg_application pa ON pa.id = fr.application_id
     JOIN admissions.pg_applicant ap ON ap.id = pa.applicant_id
     LEFT JOIN people.student s ON s.id = pa.student_id
     LEFT JOIN ref.programme p ON p.code = pa.programme_code
     LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     LEFT JOIN ref.department d ON d.code = p.dept_code
     CROSS JOIN LATERAL ( SELECT finance.categorise('PG_'::text || fr.kind, NULL::text) AS code) k
     LEFT JOIN finance.payment_category cat ON cat.code = k.code
     CROSS JOIN LATERAL ( SELECT finance.programme_type_for('POSTGRADUATE'::text, 'POST GRADUATE'::text) AS code) pt
     LEFT JOIN LATERAL finance.payment_owner(COALESCE(cat.purpose, 'OTHER'::text), pt.code) own(source_module, responsible_office) ON true
UNION ALL
 SELECT 'JUPEB'::text AS source,
    jf.id AS payment_id,
    jf.reference,
    NULL::text AS receipt_no,
    NULL::text AS purpose,
    'JUPEB_'::text || jf.kind AS kind,
    k.code AS category_code,
    jf.amount,
    jf.created_at AS generated_at,
    jf.confirmed_at,
    jf.expires_at,
    jf.channel,
    jf.session,
    NULL::uuid AS student_id,
    NULL::uuid AS application_id,
    NULL::uuid AS pg_application_id,
    ja.id::text AS payer_key,
    ja.surname,
    concat_ws(' '::text, NULLIF(btrim(ja.first_name), ''::text), NULLIF(btrim(ja.middle_name), ''::text)) AS other_names,
    ja.application_no AS number,
    ja.sex,
    'JUPEB'::text AS entry_mode,
    ja.session AS entry_session,
    ja.state AS status,
    f.code AS faculty_code,
    f.name AS faculty,
    d.code AS dept_code,
    d.name AS department,
    p.code AS programme_code,
    p.name AS programme,
    NULL::integer AS level,
    false AS is_pg,
    COALESCE(f.college_code, ''::text) = 'CHS'::text AS is_chs,
    pt.code AS programme_type,
    'JUPEB'::text AS admission_route,
    'FULL_TIME'::text AS study_mode,
    COALESCE(cat.purpose, 'OTHER'::text) AS purpose_code,
    own.source_module,
    own.responsible_office,
    jf.semester,
    NULL::text AS jamb_reg_no,
    ja.application_no,
    ja.exam_no,
    ja.id AS jupeb_application_id,
        CASE
            WHEN jf.confirmed_at IS NOT NULL THEN 'PAID'::text
            WHEN jf.expires_at <= now() THEN 'EXPIRED'::text
            ELSE 'PENDING'::text
        END AS ledger_status
   FROM jupeb.fee_reference jf
     JOIN jupeb.application ja ON ja.id = jf.application_id
     LEFT JOIN ref.programme p ON p.code = ja.programme_code
     LEFT JOIN ref.faculty f ON f.code = p.faculty_code
     LEFT JOIN ref.department d ON d.code = p.dept_code
     CROSS JOIN LATERAL ( SELECT finance.categorise('JUPEB_'::text || jf.kind, NULL::text) AS code) k
     LEFT JOIN finance.payment_category cat ON cat.code = k.code
     CROSS JOIN LATERAL ( SELECT finance.programme_type_for('JUPEB'::text, NULL::text) AS code) pt
     LEFT JOIN LATERAL finance.payment_owner(COALESCE(cat.purpose, 'OTHER'::text), pt.code) own(source_module, responsible_office) ON true;

CREATE OR REPLACE FUNCTION finance.old_fees_reconciliation(p_session text)
 RETURNS TABLE(student_id uuid, number text, name text, programme_code text, faculty_code text, level integer, due numeric, paid numeric, paid_old_s1 numeric, paid_old_s2 numeric, paid_old_session numeric, paid_payment_history numeric, paid_portal numeric, old_payments integer, difference numeric, state text, carried_in numeric, settled numeric, decision text)
 LANGUAGE sql
 STABLE
AS $function$
    WITH pay AS MATERIALIZED (
        SELECT r.student_id,
               sum(r.amount) AS paid,
               coalesce(sum(r.amount) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' AND r.purpose LIKE '% semester 1'), 0) AS s1,
               coalesce(sum(r.amount) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' AND r.purpose LIKE '% semester 2'), 0) AS s2,
               coalesce(sum(r.amount) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' AND r.purpose NOT LIKE '% semester _'), 0) AS whole,
               coalesce(sum(r.amount) FILTER (WHERE r.reference NOT LIKE 'MOAUM-%'), 0) AS hist,
               coalesce(sum(r.amount) FILTER (WHERE r.reference LIKE 'MOAUM-%' AND r.reference NOT LIKE 'MOAUM-LEG-%' AND r.channel IS DISTINCT FROM 'CARRIED'), 0) AS portal,
               coalesce(sum(r.amount) FILTER (WHERE r.channel = 'CARRIED'), 0) AS carried,
               count(*) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' OR r.reference NOT LIKE 'MOAUM-%')::int AS old_n
          FROM finance.payment_reference r
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
         GROUP BY r.student_id
        HAVING count(*) FILTER (WHERE r.reference LIKE 'MOAUM-LEG-%' OR r.reference NOT LIKE 'MOAUM-%') > 0),
    ch AS MATERIALIZED (SELECT c.student_id, c.total FROM finance.session_charges(p_session) c),
    dec AS MATERIALIZED (
        SELECT d.student_id, sum(d.amount) AS settled, string_agg(d.decision, ', ' ORDER BY d.decision) AS decision
          FROM finance.overpayment_decision d
          LEFT JOIN finance.refund rf ON d.decision = 'REFUND' AND rf.reference = d.reference
         WHERE d.session = p_session AND d.superseded_at IS NULL AND (d.decision <> 'REFUND' OR rf.state IS DISTINCT FROM 'REJECTED')
         GROUP BY d.student_id)
    SELECT p.student_id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, s.programme_code, pr.faculty_code,
           reporting.level_in_session(s.entry_level, s.entry_session, s.current_level, s.entry_mode, p_session, cy.years, cy.into_years),   -- V725
           coalesce(ch.total, 0), p.paid, p.s1, p.s2, p.whole, p.hist, p.portal, p.old_n, p.paid - coalesce(ch.total, 0),
           CASE WHEN coalesce(ch.total, 0) <= 0 THEN 'NO_FEE_STATED'
                WHEN finance.fee_short(ch.total, p.paid) THEN 'UNDER'
                WHEN p.paid - ch.total >= 1 AND p.paid - ch.total - coalesce(dec.settled, 0) < 1 THEN 'OVER_SETTLED'
                WHEN p.paid - ch.total >= 1 THEN 'OVER'
                ELSE 'MATCHED' END,
           p.carried, coalesce(dec.settled, 0), dec.decision
      FROM pay p
      JOIN people.student s ON s.id = p.student_id
      LEFT JOIN ref.programme pr ON pr.code = s.programme_code
      LEFT JOIN ch ON ch.student_id = p.student_id
      LEFT JOIN dec ON dec.student_id = p.student_id
      CROSS JOIN policy.cancelled_years() cy(years, into_years)
$function$;

CREATE OR REPLACE FUNCTION finance.overpaid(p_session text)
 RETURNS TABLE(student_id uuid, number text, name text, programme_code text, faculty_code text, level integer, due numeric, paid numeric, excess numeric, decision text, decided numeric, reference text, to_session text, decided_at timestamp with time zone, refund_state text, old_portal boolean)
 LANGUAGE sql
 STABLE
AS $function$
    WITH ch AS MATERIALIZED (SELECT c.student_id, c.total FROM finance.session_charges(p_session) c WHERE c.total > 0),
    pay AS MATERIALIZED (SELECT p.student_id, p.total FROM finance.session_payments(p_session) p),
    old AS MATERIALIZED (
        SELECT DISTINCT r.student_id FROM finance.payment_reference r
         WHERE r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'
           AND (r.reference LIKE 'MOAUM-LEG-%' OR r.reference NOT LIKE 'MOAUM-%'))
    SELECT s.id, coalesce(s.matric_no, s.admission_no), s.surname || ', ' || s.other_names, s.programme_code, pr.faculty_code,
           reporting.level_in_session(s.entry_level, s.entry_session, s.current_level, s.entry_mode, p_session, cy.years, cy.into_years),   -- V725
           ch.total, pay.total, pay.total - ch.total,
           d.decision, d.amount, d.reference, d.to_session, d.decided_at, d.refund_state, old.student_id IS NOT NULL
      FROM ch
      JOIN pay ON pay.student_id = ch.student_id AND pay.total - ch.total >= 1
      JOIN people.student s ON s.id = ch.student_id
      LEFT JOIN ref.programme pr ON pr.code = s.programme_code
      LEFT JOIN old ON old.student_id = ch.student_id
      LEFT JOIN LATERAL finance.overpayment_settled(ch.student_id, p_session) d ON true
      CROSS JOIN policy.cancelled_years() cy(years, into_years)
$function$;

CREATE OR REPLACE FUNCTION finance.import_legacy_payments(p_rows jsonb)
 RETURNS TABLE(rows integer, cleared integer, no_student integer, no_due integer, duplicates integer, duplicate_sample text, corrected integer, undated integer, matched integer, separate integer, taken_over integer)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
        v_matric text; v_session text; v_sem int; v_amount numeric; v_sid uuid; v_when timestamptz; v_given timestamptz;
        v_ref text; v_base text; v_base0 text; v_rcpt text; v_key text; v_tag text; v_note text; v_cnt int;
        v_level int; v_item text; v_free text; v_text text; v_other boolean; v_gst boolean; v_slug text;
        v_old_ref text; v_payref text; v_channel text; v_separate boolean; st people.student; ex finance.payment_reference;
        ph finance.payment_reference; gf record; rs record; v_purpose text;
        v_reason text := coalesce(nullif(btrim(coalesce(current_setting('moaum.reason', true), '')), ''), 'the old portal''s export names this payment');
        n int := 0; nc int := 0; nns int := 0; nnd int := 0; nd int := 0; nfix int := 0; nund int := 0; nm int := 0; nsep int := 0; ntk int := 0;
        v_dups text[] := '{}';
        v_cy_years integer[]; v_cy_into integer[];   -- V725: the cancelled years, read once a call
BEGIN
    SELECT c.years, c.into_years INTO v_cy_years, v_cy_into FROM policy.cancelled_years() c;   -- V725
    IF v_actor IS NULL THEN RAISE EXCEPTION 'a legacy payment is recorded by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' OR jsonb_array_length(p_rows) = 0 THEN
        RAISE EXCEPTION 'the payments are rows: matriculation number, session, amount (or blank for cleared in full)' USING ERRCODE = '23514';
    END IF;

    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_matric := upper(btrim(coalesce(r->>'matric', r->>'matricNo', r->>'matric_no', r->>'matno', r->>'regNo', '')));
        v_session := btrim(coalesce(r->>'session', ''));
        IF v_matric = '' OR v_session !~ '^[0-9]{4}/[0-9]{4}$' THEN CONTINUE; END IF;
        IF v_matric ~* '^mat(ric|no)' THEN CONTINUE; END IF;   -- a header row
        n := n + 1;

        -- V647: the payer's number resolved by the authoritative records — the matriculation number, an old one a correction
        -- replaced, the admission number, and (not for an applicant's payment) the JAMB registration or application number naming
        -- one student; a row the records give no student, or several, is held for the reconciliation instead of dropped
        v_purpose := finance.legacy_row_purpose(r);
        SELECT * INTO rs FROM people.resolve_student(v_matric, v_purpose <> 'APPLICANT');
        IF rs.student_id IS NULL THEN
            PERFORM finance.legacy_hold(r, v_matric, v_purpose, rs.identifier_type, rs.status, rs.candidates);
            nns := nns + 1; CONTINUE;
        END IF;
        SELECT * INTO st FROM people.student WHERE id = rs.student_id;
        v_sid := st.id;

        v_sem := finance.legacy_semester(coalesce(r->>'semester', r->>'sem'));

        -- what the money was for: the old portal's payment item when the file carries one (it is what it says);
        -- else the free-text Note, which is another purpose only when it names one
        v_item := finance.legacy_item_of(coalesce(r->>'purpose', r->>'item', r->>'payItem', r->>'paymentItem', r->>'feeType', ''));   -- V498: a code is the item it names
        v_free := btrim(coalesce(r->>'note', ''));
        v_text := CASE WHEN v_item <> '' THEN v_item ELSE v_free END;
        v_gst := coalesce(finance.legacy_gst_type_of(v_text), '') = 'GST';
        v_other := NOT v_gst AND v_text <> '' AND v_text !~* '(school|tuition|semester fee|session fee)'
                   AND (v_item <> ''
                        OR v_text ~* '(^|[^a-z])(gst|gns|general stud|hostel|accommodation|transcript|library|deferment|transfer|wallet|acceptance|application|post-?utme|screening|medical|id card|convocation|late registration|clearance|siwes|certificate|verification|result|change of|add(-| )?drop|carry-?over|exam|fine|penalty|levy|dues|insurance|sports|development|laboratory|lab|studio|field|excursion|matriculation|thesis|project|supervision|bench|departmental|faculty)');
        v_slug := CASE WHEN v_gst THEN 'GST' WHEN v_other THEN left(regexp_replace(upper(v_text), '[^0-9A-Z]', '', 'g'), 20) END;

        v_key := replace(v_session, '/', '-');
        v_base0 := 'MOAUM-LEG-' || regexp_replace(v_matric, '[^0-9A-Z]', '', 'g') || '-' || v_key;      -- the whole-session school-fees reference
        v_base := v_base0 || CASE WHEN v_sem IS NOT NULL THEN '-S' || v_sem ELSE '' END;                -- this row's school-fees reference
        v_ref := v_base || CASE WHEN v_slug IS NOT NULL THEN '-' || v_slug ELSE '' END;

        -- the date the student paid, as the file gives it
        v_given := finance.legacy_date(coalesce(r->>'paidOn', r->>'paid_on', r->>'date'));
        v_amount := nullif(regexp_replace(coalesce(r->>'amount', r->>'amountPaid', r->>'paid', ''), '[^0-9.]', '', 'g'), '')::numeric;

        -- the purpose as the ledger names it: the GST fee is one per session, and is what the GST desk counts
        v_tag := CASE WHEN v_gst THEN 'GST fee ' || v_session
                      ELSE (CASE WHEN v_other THEN v_text ELSE 'School fees' END) || ' (legacy)'
                           || CASE WHEN v_sem IS NOT NULL THEN ' · semester ' || v_sem ELSE '' END END;

        v_old_ref := btrim(coalesce(r->>'receiptNo', r->>'reference', r->>'receipt', r->>'payref', ''));
        v_payref := nullif(upper(v_old_ref), '');
        v_channel := btrim(coalesce(r->>'channel', ''));
        v_note := coalesce(nullif(v_free, ''), 'Imported from the old portal')
                  || CASE WHEN v_channel <> '' AND v_channel !~* '^(old record|legacy)$' THEN ' · ' || v_channel ELSE '' END
                  || CASE WHEN v_old_ref <> '' THEN ' · old ref ' || v_old_ref ELSE '' END;
        v_separate := false;

        IF v_payref IS NOT NULL THEN
            -- V498: the old portal's payment number decides. Seen before: that payment again, never a second one
            -- V561: and a payment withdrawn because the bank never received it stays withdrawn when the export names it again
            IF EXISTS (SELECT 1 FROM finance.legacy_payref k WHERE k.payref = v_payref)
               OR EXISTS (SELECT 1 FROM finance.legacy_payref_withdrawn w WHERE w.payref = v_payref) THEN
                nd := nd + 1; v_dups := v_dups || v_payref;
                CONTINUE;
            END IF;
            -- a record already there for this key that this payment is (part of), recorded by an upload that did not keep the
            -- number: what the record holds beyond the payments already attached to it is this payment's amount (the same day
            -- first) — or, on a record the 15 Sep 2026 migration summed from several payments, has room for it. The same amount
            -- is within a naira: that migration kept whole naira (36,556.00 for the export's 36,555.80), as finance.fee_short reads
            SELECT x.* INTO ex FROM finance.payment_reference x
              LEFT JOIN LATERAL (SELECT count(*) AS n, coalesce(sum(coalesce(k.amount, x.amount)), 0) AS held
                                   FROM finance.legacy_payref k WHERE k.reference = x.reference) c ON true
             WHERE x.student_id = v_sid AND x.channel = 'Legacy'
               AND (x.reference = v_ref
                    OR (v_sem IS NULL AND v_slug IS NULL AND x.reference IN (v_base0 || '-S1', v_base0 || '-S2', v_base0 || '-S3')))
               AND CASE WHEN v_amount IS NULL THEN c.n = 0
                        WHEN x.note ~ '^[2-9][0-9]* school-fees payment\(s\), migrated' THEN x.amount - c.held - v_amount > -1
                        ELSE abs(x.amount - c.held - v_amount) < 1 END
             ORDER BY (v_given IS NOT NULL AND (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (v_given AT TIME ZONE 'Africa/Lagos')::date) DESC,
                      abs(x.amount - c.held - coalesce(v_amount, x.amount - c.held)), (x.reference = v_ref) DESC
             LIMIT 1;
            IF ex.id IS NOT NULL THEN
                INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (v_payref, ex.reference, coalesce(v_amount, ex.amount));
                -- a summed record keeps its day; one payment's record takes the day the file gives
                IF ex.archived_at IS NOT NULL THEN
                    NULL;   -- V670: an archived record keeps its day and note; its number is known now
                ELSIF v_given IS NOT NULL AND ex.note !~ '^[2-9][0-9]* school-fees payment\(s\), migrated'
                   AND (ex.confirmed_at AT TIME ZONE 'Africa/Lagos')::date IS DISTINCT FROM (v_given AT TIME ZONE 'Africa/Lagos')::date THEN
                    UPDATE finance.payment_reference SET confirmed_at = v_given, expires_at = v_given,
                           note = CASE WHEN note LIKE '%old ref %' THEN note ELSE v_note END
                     WHERE id = ex.id;
                    nfix := nfix + 1;
                ELSIF ex.note NOT LIKE '%old ref %' AND ex.archived_at IS NULL THEN
                    UPDATE finance.payment_reference SET note = v_note WHERE id = ex.id;
                END IF;
                nm := nm + 1;
                CONTINUE;
            END IF;
            -- the key is held by another payment (one with its own number, or another amount): this one is its own record
            IF EXISTS (SELECT 1 FROM finance.payment_reference WHERE reference = v_ref) THEN
                v_ref := v_ref || '-' || left(regexp_replace(v_payref, '[^0-9A-Z]', '', 'g'), 30);
                v_separate := true;
            END IF;
        ELSE
            -- a file without payment numbers, read as before: already on record, skip and report; the amount is never touched
            -- (a wrong date is put right)
            SELECT * INTO ex FROM finance.payment_reference WHERE reference = v_ref;
            -- V670: the key held by a record archived for good of another amount: this payment is its own record beside it
            IF ex.id IS NOT NULL AND ex.archived_at IS NOT NULL AND v_amount IS NOT NULL AND abs(ex.amount - v_amount) >= 1 THEN
                v_ref := v_ref || '-A' || to_char(round(v_amount), 'FM999999999990');
                ex := NULL;
                SELECT * INTO ex FROM finance.payment_reference WHERE reference = v_ref;
            END IF;
            IF ex.id IS NOT NULL THEN
                IF ex.channel = 'Legacy' AND ex.archived_at IS NULL AND v_given IS NOT NULL AND ex.confirmed_at IS DISTINCT FROM v_given
                   AND (v_amount IS NULL OR v_amount = ex.amount) THEN
                    UPDATE finance.payment_reference SET confirmed_at = v_given, expires_at = v_given WHERE id = ex.id;
                    nfix := nfix + 1;
                ELSE
                    nd := nd + 1; v_dups := v_dups || v_ref;
                END IF;
                CONTINUE;
            END IF;

            -- V449: this row names no semester and no other item, and an earlier upload already put the same money on the ledger
            -- per semester (this reference with -S1, -S2 or -S3), for the same amount and, when the file gives one, the same day
            IF v_sem IS NULL AND v_slug IS NULL AND v_amount IS NOT NULL
               AND EXISTS (SELECT 1 FROM finance.payment_reference x
                            WHERE x.reference IN (v_base0 || '-S1', v_base0 || '-S2', v_base0 || '-S3')
                              AND x.channel = 'Legacy' AND x.amount = v_amount
                              AND (v_given IS NULL OR (x.confirmed_at AT TIME ZONE 'Africa/Lagos')::date = (v_given AT TIME ZONE 'Africa/Lagos')::date)) THEN
                nd := nd + 1; v_dups := v_dups || v_ref;
                CONTINUE;
            END IF;
        END IF;

        -- the same money already on the ledger as school fees from an upload that could not tell more — without this row's
        -- semester, or without its item: put the semester on it, or relabel it; one row, not two (never for a payment that is
        -- its own record beside another of the same key, and never a record that already carries a payment number)
        IF NOT v_separate AND v_amount IS NOT NULL AND (v_sem IS NOT NULL OR v_slug IS NOT NULL) THEN
            SELECT * INTO ex FROM finance.payment_reference x
             WHERE x.reference IN (v_base0, v_base) AND x.reference <> v_ref AND x.channel = 'Legacy'
               AND x.purpose LIKE 'School fees%' AND abs(x.amount - v_amount) < 1
               AND NOT EXISTS (SELECT 1 FROM finance.legacy_payref k WHERE k.reference = x.reference)
             ORDER BY (x.reference = v_base) DESC LIMIT 1;
            IF ex.id IS NOT NULL AND ex.archived_at IS NOT NULL THEN
                nd := nd + 1; v_dups := v_dups || v_ref;   -- V670: the same money is on record, archived for review
                CONTINUE;
            END IF;
            IF ex.id IS NOT NULL THEN
                v_when := coalesce(v_given, ex.confirmed_at);
                UPDATE finance.payment_reference
                   SET reference = v_ref, receipt_no = 'LEG-' || v_ref, purpose = v_tag, confirmed_at = v_when, expires_at = v_when,
                       note = CASE WHEN v_free <> '' OR v_old_ref <> '' THEN v_note ELSE note END
                 WHERE id = ex.id;
                IF v_payref IS NOT NULL THEN
                    INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (v_payref, v_ref, ex.amount);
                END IF;
                nfix := nfix + 1;
                CONTINUE;
            END IF;
        END IF;

        -- V502: the retired Payment History Upload recorded this payment under its number (as the reference, or the receipt) and
        -- no Old Fees History record has it: that record becomes the one this row makes — the item, the semester, the day paid,
        -- the session — so the payment is on record once. That door read every row as school fees whatever it was, without a
        -- semester, and dated a row it could not read with the day of the upload. Its ledger posting is let go (reversed and
        -- freed), so the sync posts the payment again under its item; a record something points at by its reference is left.
        IF v_payref IS NOT NULL THEN
            ph := NULL;
            SELECT x.* INTO ph FROM finance.payment_reference x
             WHERE x.student_id = v_sid AND x.reference NOT LIKE 'MOAUM-%' AND x.confirmed_at IS NOT NULL
               AND (upper(btrim(x.reference)) = v_payref OR upper(btrim(x.receipt_no)) = v_payref)
               AND NOT finance.payment_reference_linked(x.reference, x.id)
             ORDER BY (upper(btrim(x.reference)) = v_payref) DESC, x.reference
             LIMIT 1;
            IF ph.id IS NOT NULL AND ph.archived_at IS NOT NULL THEN
                nd := nd + 1; v_dups := v_dups || v_ref;   -- V670: recorded already, archived for review
                CONTINUE;
            END IF;
            IF ph.id IS NOT NULL THEN
                IF EXISTS (SELECT 1 FROM finance.payment_reference x WHERE (x.reference = v_ref OR x.receipt_no = 'LEG-' || v_ref) AND x.id <> ph.id) THEN
                    v_ref := v_ref || '-' || left(regexp_replace(v_payref, '[^0-9A-Z]', '', 'g'), 30);
                END IF;
                SELECT * INTO gf FROM finance.gl_free_payment(ph.reference, ph.id, 'PAYMENT_CORRECTED',
                    'the payment ' || ph.reference || ' recorded by Payment History Upload is ' || v_tag || ' (' || v_ref || '): ' || v_reason);
                v_when := coalesce(v_given, ph.confirmed_at);
                UPDATE finance.payment_reference
                   SET reference = v_ref, receipt_no = 'LEG-' || v_ref, purpose = v_tag, session = v_session,
                       amount = coalesce(v_amount, amount), confirmed_at = v_when, expires_at = v_when, channel = 'Legacy',
                       note = v_note || ' · first recorded by Payment History Upload as ' || ph.reference
                 WHERE id = ph.id;
                INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (v_payref, v_ref, coalesce(v_amount, ph.amount));
                INSERT INTO finance.legacy_item_corrected (payment_id, old_reference, new_reference, old_purpose, new_purpose, action,
                                                           ledger_journal, reversal_journal, corrected_by, reason)
                VALUES (ph.id, ph.reference, v_ref, ph.purpose, v_tag, 'TAKEN_OVER', gf.journal, gf.reversal, v_actor, v_reason);
                ntk := ntk + 1;
                CONTINUE;
            END IF;
        END IF;

        IF v_amount IS NULL THEN
            -- the level the student was at in THAT session, unless the file says
            v_level := nullif(regexp_replace(coalesce(r->>'level', ''), '[^0-9]', '', 'g'), '')::int;
            IF v_level IS NULL OR v_level NOT IN (100, 200, 300, 400, 500, 600) THEN
                v_level := reporting.level_in_session(st.entry_level, st.entry_session, st.current_level, st.entry_mode, v_session, v_cy_years, v_cy_into);   -- V725
            END IF;
            SELECT coalesce(sum(f.amount), 0) INTO v_amount
              FROM finance.fee_schedule f
              JOIN ref.programme p ON p.code = st.programme_code
             WHERE f.session = v_session AND f.ended_at IS NULL
               AND (f.level IS NULL OR f.level = v_level)
               AND (f.entry_mode IS NULL OR f.entry_mode = st.entry_mode)
               AND (f.faculty_code IS NULL OR f.faculty_code = p.faculty_code)
               AND (f.programme_code IS NULL OR f.programme_code = st.programme_code)
               AND (v_sem IS NULL OR f.semester IS NULL OR f.semester = v_sem)
               AND CASE WHEN v_gst THEN f.item ~* '(gst|gns|general stud)'
                        WHEN v_other THEN f.item ILIKE '%' || v_text || '%'
                        ELSE f.item ILIKE 'school fee%' END;
            IF v_gst AND (v_amount IS NULL OR v_amount <= 0) THEN
                SELECT g.amount INTO v_amount FROM finance.gst_fee_for(v_sid, v_session) g WHERE g.stated;
            END IF;
        END IF;
        IF v_amount IS NULL OR v_amount <= 0 THEN nnd := nnd + 1; CONTINUE; END IF;

        v_when := v_given;
        IF v_when IS NULL THEN v_when := now(); nund := nund + 1; END IF;
        v_rcpt := 'LEG-' || v_ref;

        INSERT INTO finance.payment_reference
            (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no, note)
        VALUES (v_sid, v_session, v_ref, v_tag, v_amount, v_when, v_when, v_actor, 'Legacy', v_rcpt, v_note)
        ON CONFLICT (reference) DO NOTHING;
        GET DIAGNOSTICS v_cnt = ROW_COUNT;
        IF v_cnt > 0 THEN
            nc := nc + 1;
            IF v_separate THEN nsep := nsep + 1; END IF;
            IF v_payref IS NOT NULL THEN
                INSERT INTO finance.legacy_payref (payref, reference, amount) VALUES (v_payref, v_ref, v_amount);
            END IF;
            -- V647: paid under another number (a JAMB registration, application or admission number, an old matriculation number):
            -- the number kept beside the payment, which is the same payment, counted once
            IF upper(coalesce(st.matric_no, '')) <> v_matric THEN
                INSERT INTO finance.payment_identity (payment_id, original_identifier, original_identifier_type, resolved_student_id, resolved_matric_no,
                                                      match_method, source, batch_ref, recorded_by)
                SELECT pr.id, v_matric, rs.identifier_type, v_sid, st.matric_no, rs.method,
                       CASE WHEN nullif(current_setting('moaum.recon_batch', true), '') IS NULL THEN 'OLD_FEES_IMPORT' ELSE 'FEE_HISTORY_RECONCILIATION' END,
                       nullif(current_setting('moaum.recon_batch', true), ''), v_actor
                  FROM finance.payment_reference pr WHERE pr.reference = v_ref
                ON CONFLICT (payment_id) DO NOTHING;
            END IF;
            -- a row held before, recorded now
            UPDATE finance.legacy_payment_held h
               SET status = 'RECONCILED', payment_id = (SELECT pr.id FROM finance.payment_reference pr WHERE pr.reference = v_ref), reconciled_at = now(),
                   batch_ref = coalesce(nullif(current_setting('moaum.recon_batch', true), ''), h.batch_ref)
             WHERE h.row_key = coalesce('PAYREF:' || v_payref, 'ROW:' || md5(r::text)) AND h.status <> 'RECONCILED';
        ELSE
            nd := nd + 1; v_dups := v_dups || coalesce(v_payref, v_ref);
        END IF;
    END LOOP;

    RETURN QUERY SELECT n, nc, nns, nnd, nd, array_to_string(v_dups, ', '), nfix, nund, nm, nsep, ntk;
END $function$;

-- ── 6 · a merger marks the historical summaries stale ──────────────────────────────────────────────────────────────────
ALTER TABLE finance.historical_bound DROP CONSTRAINT historical_bound_stream_check,
    ADD CONSTRAINT historical_bound_stream_check CHECK (stream IN ('UG', 'PG', 'CCE', 'MERGES'));
INSERT INTO finance.historical_bound (stream, last_session)
SELECT 'MERGES', coalesce(string_agg(a.name || '>' || coalesce(a.merged_into, ''), ',' ORDER BY a.name), '')
  FROM policy.academic_session a WHERE a.state = 'CANCELLED'
ON CONFLICT (stream) DO NOTHING;
COMMENT ON TABLE finance.historical_bound IS
  'V723, V725: the end of a studying student''s past on each calendar (UG, PG, CCE: the session before its current one) and the sessions merged (MERGES: cancelled > merged into) as last seen — a move marks the students it concerns stale.';

CREATE OR REPLACE FUNCTION finance.historical_bounds_moved()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE v_moved text[]; n int := 0; v_merges text; m int := 0;
BEGIN
    -- V725: a session merged (or the merger undone) changes how every student's sessions are counted — the levels of past periods
    -- and so their fee lines (a postgraduate student's periods in a merged session too): every student of the population is marked stale
    SELECT coalesce(string_agg(a.name || '>' || coalesce(a.merged_into, ''), ',' ORDER BY a.name), '') INTO v_merges
      FROM policy.academic_session a WHERE a.state = 'CANCELLED';
    UPDATE finance.historical_bound b SET last_session = v_merges, moved_at = now() WHERE b.stream = 'MERGES' AND b.last_session IS DISTINCT FROM v_merges;
    IF FOUND THEN
        INSERT INTO finance.historical_stale (student_id)
        SELECT s.id FROM people.student s WHERE finance.historical_population(s.status, s.id, s.entry_session)
        ON CONFLICT (student_id) DO UPDATE SET marked_at = now();
        GET DIAGNOSTICS m = ROW_COUNT;
    END IF;
    WITH now_seen(stream, s) AS (VALUES
            ('UG', finance.session_before(policy.university_current_session())),
            ('PG', finance.session_before(coalesce((SELECT a.name FROM admissions.pg_academic_session a WHERE a.state = 'CURRENT' ORDER BY a.name DESC LIMIT 1),
                                                   policy.university_current_session()))),
            ('CCE', finance.session_before(coalesce(policy.route_session('CCE'), policy.university_current_session())))),
         moved AS (
            UPDATE finance.historical_bound b SET last_session = x.s, moved_at = now()
              FROM now_seen x WHERE b.stream = x.stream AND b.last_session IS DISTINCT FROM x.s
            RETURNING b.stream)
    SELECT array_agg(m.stream) INTO v_moved FROM moved m;
    IF v_moved IS NULL THEN RETURN m; END IF;
    -- the students whose past ends on a calendar: studying (ACTIVE, PROBATION), no award approved — the population's part bounded by it
    INSERT INTO finance.historical_stale (student_id)
    SELECT s.id FROM people.student s
     WHERE s.status IN ('ACTIVE', 'PROBATION') AND s.entry_session IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED')
       AND (CASE WHEN s.entry_mode = 'CCE' THEN 'CCE' WHEN s.entry_mode = 'POSTGRADUATE' THEN 'PG' ELSE 'UG' END) = ANY (v_moved)
    ON CONFLICT (student_id) DO UPDATE SET marked_at = now();
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n + m;
END $function$;
COMMENT ON FUNCTION finance.historical_bounds_moved() IS
  'V723, V725: whether the end of a studying student''s past moved on any calendar since last seen (that calendar''s studying students marked stale), or a session was merged or its merger undone (every student of the population marked stale); returns the students marked.';

-- ── 7 · once: the students whose count changes here marked stale; what a person decided at the old count, told ─────────────
INSERT INTO finance.historical_stale (student_id)
SELECT s.id FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code
 WHERE finance.historical_population(s.status, s.id, s.entry_session) AND NOT people.is_postgraduate(s.entry_mode, p.category)
   AND (policy.session_year(policy.session_normal(s.entry_session)) <= (SELECT max(policy.session_year(a.name)) FROM policy.academic_session a WHERE a.state = 'CANCELLED')
        OR NOT EXISTS (SELECT 1 FROM policy.academic_session a WHERE a.name = s.entry_session))
ON CONFLICT (student_id) DO UPDATE SET marked_at = now();

DO $$
DECLARE v_marked int; v_assess int; v_moves int;
BEGIN
    SELECT count(*) INTO v_marked FROM finance.historical_stale;
    -- a historical assessment or a payment reallocation made before V725 names the level it was made at; they are listed, not changed
    SELECT count(*) INTO v_assess FROM finance.historical_assessment a JOIN people.student s ON s.id = a.student_id
     WHERE a.state IN ('DRAFT', 'PENDING_BURSAR_APPROVAL', 'RETURNED_FOR_CORRECTION', 'APPROVED')
       AND a.level IS DISTINCT FROM people.level_in(a.student_id, a.session, a.semester);
    SELECT count(*) INTO v_moves FROM finance.payment_reallocation r
     WHERE r.to_level IS DISTINCT FROM people.level_in(r.student_id, r.to_session);
    RAISE NOTICE 'V725: % historical summaries to work out again; % historical assessments and % payment reallocations name a level other than the session''s count now (listed for the Bursary, not changed)',
        v_marked, v_assess, v_moves;
END $$;

COMMIT;
