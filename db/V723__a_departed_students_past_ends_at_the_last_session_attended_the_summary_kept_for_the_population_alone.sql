-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V723 · The follow-ups of V720's review: a departed student's past ends at the last session they attended; the School of
--         Postgraduate Studies' calendar read directly; the historical summary kept for the population alone
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V720 opened the historical engine's summary, stale marks and pay door to every student. Read again (11 November 2026):
--    1 · finance.historical_rows_read bounded every student not graduated by the session before their calendar's current one —
--        a student WITHDRAWN, EXPELLED, TRANSFERRED_OUT, RUSTICATED, DORMANT, DECEASED or on VOLUNTARY_WITHDRAWAL years ago read as
--        owing every session since, sessions they never attended; V720's payment trigger then kept a summary for them, and the
--        pay door would have taken their money for those sessions. A student who has left (or was admitted and never came) is
--        now bounded by the last session they enrolled or registered in, as records.graduation_session falls back for a graduate
--        with no graduand row — never past the calendar's bound; with no such session, no past at all. A student studying, deferred
--        or suspended keeps the calendar's bound. The pay door follows the account: it is not changed.
--    2 · A postgraduate student's bound read admissions.pg_current_session(), whose literal fallback ('2025/2026') is reached when
--        the School has no CURRENT row and the University's calendar is between sessions: their last finished session dropped
--        off the account. The School's own CURRENT row is read directly, the University's session when it has none.
--    3 · The payment trigger marked any student stale and finance.historical_refresh worked out any student it was given by name,
--        so a student outside the population (finance.historical_population: ACTIVE, PROBATION, GRADUATED, an approved graduand)
--        could gain a summary and so a place on the desk's lists. The trigger marks the population alone; historical_refresh
--        given names outside it removes their summary and mark; a change of status or entry session (a trigger on people.student)
--        or of an award's approval (a trigger on records.graduand) marks the student stale when in the population — an existing
--        summary too, since the first or last session moved — and removes summary and mark when out of it; summaries and marks
--        outside the population are removed once here. The postgraduate population is
--        marked stale once, so the bound of 2 is worked out again by the next desk reads.
--    4 · A calendar's move (a session made current on the University's, the School's or the Centre's calendar) ends every studying
--        student's past one session on, but marked nothing: their summaries kept the old end until a payment came. The end last
--        seen on each calendar is kept (finance.historical_bound); a statement on a calendar that moves it marks that calendar's
--        studying students stale.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V723: a departed student''s past ends at the last session attended; the summary kept for the population alone (the review of V720, 11 November 2026)', true);

-- ── 1 · the engine: a departed student's past ends at the last session attended; the School's calendar read directly ──────
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
    -- the calendar's order, as people.level_in counts the sessions since admission (every session row, by its start)
    cal AS MATERIALIZED (SELECT a.name, a.state, a.semesters, row_number() OVER (ORDER BY a.starts_on, a.name) AS idx FROM policy.academic_session a),
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

COMMENT ON FUNCTION finance.historical_rows_read(uuid[]) IS
  'V654…V720, V723: every session of each student''s record from the assessment start to the end of their past — a graduate''s graduation session, a student studying (or deferred, or suspended) the session before their own calendar''s current one (the University''s, the School of Postgraduate Studies'' own CURRENT row, the Centre''s), a student who has left the last session they enrolled or registered in — each period at the level of the session, assessed as the student was then, the session''s payments first semester first.';

-- ── 2 · the summary: the population alone ────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.historical_refresh(p_students uuid[] DEFAULT NULL::uuid[])
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE v_ids uuid[]; n int;
BEGIN
    -- V720: every student the historical account is read for — studying, on probation or graduated (and an approved graduand)
    v_ids := coalesce(p_students, (SELECT array_agg(s.id) FROM people.student s WHERE finance.historical_population(s.status, s.id, s.entry_session)));
    -- V723: given students by name, only those of the population are worked out; the others keep no summary and no stale mark
    IF p_students IS NOT NULL THEN
        DELETE FROM finance.historical_summary h WHERE h.student_id = ANY (p_students)
           AND NOT EXISTS (SELECT 1 FROM people.student s WHERE s.id = h.student_id AND finance.historical_population(s.status, s.id, s.entry_session));
        DELETE FROM finance.historical_stale x WHERE x.student_id = ANY (p_students)
           AND NOT EXISTS (SELECT 1 FROM people.student s WHERE s.id = x.student_id AND finance.historical_population(s.status, s.id, s.entry_session));
        SELECT array_agg(s.id) INTO v_ids FROM people.student s WHERE s.id = ANY (p_students) AND finance.historical_population(s.status, s.id, s.entry_session);
    END IF;
    IF v_ids IS NULL OR cardinality(v_ids) = 0 THEN
        IF p_students IS NULL THEN UPDATE finance.historical_setting SET refreshed_at = now() WHERE id = 1; END IF;
        RETURN 0;
    END IF;
    WITH hr AS (SELECT * FROM finance.historical_rows(v_ids)),
    agg AS (
        SELECT r.student_id, min(r.session) AS first_session, max(r.session) AS last_session, count(*)::int AS periods,
               coalesce(sum(r.assessed), 0) AS assessed, coalesce(sum(r.paid), 0) AS paid, coalesce(sum(r.outstanding), 0) AS outstanding,
               coalesce(sum(r.credit), 0) AS credit, coalesce(sum(r.waived), 0) AS waived,
               count(*) FILTER (WHERE r.outstanding > 0)::int AS owing_periods,
               count(*) FILTER (WHERE r.status = 'REQUIRES_REVIEW')::int AS review_periods,
               count(*) FILTER (WHERE r.status = 'PENDING_APPROVAL')::int AS pending_periods,
               count(*) FILTER (WHERE r.status = 'PARTIALLY_PAID')::int AS partial_periods,
               string_agg(r.session || ' S' || r.semester, ', ' ORDER BY r.session, r.semester) FILTER (WHERE r.outstanding > 0) AS owing
          FROM hr r GROUP BY r.student_id),
    -- V720: a session owed in whole (nothing of it paid) and one owed in part, counted a student
    ses AS (
        SELECT r.student_id, count(*) FILTER (WHERE r.outstanding > 0 AND r.paid = 0)::int AS whole_sessions,
               count(*) FILTER (WHERE r.outstanding > 0 AND r.paid > 0)::int AS part_sessions
          FROM (SELECT x.student_id, x.session, coalesce(sum(x.outstanding), 0) AS outstanding, coalesce(sum(x.paid), 0) AS paid
                  FROM hr x GROUP BY x.student_id, x.session) r
         GROUP BY r.student_id),
    ids AS (SELECT DISTINCT unnest(v_ids) AS student_id),
    up AS (
        INSERT INTO finance.historical_summary AS h (student_id, first_session, last_session, periods, assessed, paid, outstanding, credit, owing_periods,
                                                     review_periods, pending_periods, partial_periods, owing, financial_status, last_payment_at, refreshed_at, waived,
                                                     whole_sessions, part_sessions)
        SELECT i.student_id, a.first_session, a.last_session, coalesce(a.periods, 0), coalesce(a.assessed, 0), coalesce(a.paid, 0), coalesce(a.outstanding, 0),
               coalesce(a.credit, 0), coalesce(a.owing_periods, 0), coalesce(a.review_periods, 0), coalesce(a.pending_periods, 0), coalesce(a.partial_periods, 0), a.owing,
               CASE WHEN coalesce(a.periods, 0) = 0 THEN 'NO_HISTORICAL_PERIOD'
                    WHEN a.review_periods > 0 THEN 'HISTORICAL_FEE_REVIEW_REQUIRED'
                    WHEN a.pending_periods > 0 THEN 'FINANCIAL_CLEARANCE_PENDING'
                    WHEN a.outstanding > 0 THEN 'FINANCIAL_OBLIGATION'
                    ELSE 'FINANCIALLY_CLEARED' END,
               (SELECT max(r.confirmed_at) FROM finance.payment_reference r WHERE r.student_id = i.student_id AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL AND r.purpose LIKE 'School fees%'),
               now(), coalesce(a.waived, 0), coalesce(se.whole_sessions, 0), coalesce(se.part_sessions, 0)
          FROM ids i LEFT JOIN agg a ON a.student_id = i.student_id LEFT JOIN ses se ON se.student_id = i.student_id
        ON CONFLICT (student_id) DO UPDATE SET first_session = EXCLUDED.first_session, last_session = EXCLUDED.last_session, periods = EXCLUDED.periods,
            assessed = EXCLUDED.assessed, paid = EXCLUDED.paid, outstanding = EXCLUDED.outstanding, credit = EXCLUDED.credit,
            owing_periods = EXCLUDED.owing_periods, review_periods = EXCLUDED.review_periods, pending_periods = EXCLUDED.pending_periods,
            partial_periods = EXCLUDED.partial_periods, owing = EXCLUDED.owing, financial_status = EXCLUDED.financial_status,
            last_payment_at = EXCLUDED.last_payment_at, refreshed_at = EXCLUDED.refreshed_at, waived = EXCLUDED.waived,
            whole_sessions = EXCLUDED.whole_sessions, part_sessions = EXCLUDED.part_sessions
        RETURNING 1)
    SELECT count(*) INTO n FROM up;
    DELETE FROM finance.historical_stale x WHERE x.student_id = ANY (v_ids);
    IF p_students IS NULL THEN UPDATE finance.historical_setting SET refreshed_at = now() WHERE id = 1; END IF;
    RETURN n;
END $function$;

COMMENT ON FUNCTION finance.historical_refresh(uuid[]) IS
  'V654, V665, V720, V723: the historical summary of the students given — those of the population (finance.historical_population); the others lose any summary and mark — or, given none, of the whole population, worked out again from finance.historical_rows; the sessions owed in whole and in part counted; the stale marks cleared.';

CREATE OR REPLACE FUNCTION finance.trg_historical_stale_payment() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
    -- V720: a school-fee payment marks its student stale whether or not a summary exists yet; V723: a student of the population alone
    IF NEW.student_id IS NOT NULL AND NEW.purpose LIKE 'School fees%'
       AND EXISTS (SELECT 1 FROM people.student s WHERE s.id = NEW.student_id AND finance.historical_population(s.status, s.id, s.entry_session)) THEN
        INSERT INTO finance.historical_stale (student_id) VALUES (NEW.student_id) ON CONFLICT (student_id) DO NOTHING;
    END IF;
    RETURN NEW;
END $function$;

-- a status change puts a student into the population (marked stale, worked out by the next desk read) or out of it (summary and mark removed)
-- a student's standing decides whether a summary is kept: in the population it is marked stale (an existing summary too — a corrected
-- entry session moves the first session, a graduation moves the last), out of it the summary and mark are removed
CREATE OR REPLACE FUNCTION finance.historical_mark(p_student uuid) RETURNS void LANGUAGE plpgsql AS $function$
BEGIN
    IF EXISTS (SELECT 1 FROM people.student s WHERE s.id = p_student AND finance.historical_population(s.status, s.id, s.entry_session)) THEN
        INSERT INTO finance.historical_stale (student_id) VALUES (p_student) ON CONFLICT (student_id) DO UPDATE SET marked_at = now();
    ELSE
        DELETE FROM finance.historical_summary h WHERE h.student_id = p_student;
        DELETE FROM finance.historical_stale x WHERE x.student_id = p_student;
    END IF;
END $function$;
COMMENT ON FUNCTION finance.historical_mark(uuid) IS
  'V723: a student whose standing or bound changed — in the historical population, their summary is marked stale (worked out again by the next desk read); out of it, their summary and mark are removed.';

-- a status or entry session changed on the register
CREATE OR REPLACE FUNCTION finance.trg_historical_population_status() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
    PERFORM finance.historical_mark(NEW.id);
    RETURN NEW;
END $function$;
COMMENT ON FUNCTION finance.trg_historical_population_status() IS
  'V723: a student whose status or entry session changes is marked stale when in the historical population (an existing summary too), or loses summary and mark when out of it.';
DROP TRIGGER IF EXISTS trg_historical_population_status ON people.student;
CREATE TRIGGER trg_historical_population_status AFTER UPDATE OF status, entry_session ON people.student
    FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status OR OLD.entry_session IS DISTINCT FROM NEW.entry_session)
    EXECUTE FUNCTION finance.trg_historical_population_status();

-- the Senate's approval (or its withdrawal) of an award: the bound moves to the graduation session, and the population may change
CREATE OR REPLACE FUNCTION finance.trg_historical_graduand() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
    -- only an approved award moves the bound or the population: an entry on the graduation list awaiting the Senate changes neither
    IF TG_OP = 'DELETE' THEN
        IF OLD.senate_state = 'APPROVED' THEN PERFORM finance.historical_mark(OLD.student_id); END IF;
        RETURN OLD;
    END IF;
    IF TG_OP = 'INSERT' THEN
        IF NEW.senate_state = 'APPROVED' THEN PERFORM finance.historical_mark(NEW.student_id); END IF;
        RETURN NEW;
    END IF;
    IF OLD.senate_state = 'APPROVED' OR NEW.senate_state = 'APPROVED' THEN
        PERFORM finance.historical_mark(NEW.student_id);
        IF OLD.student_id IS DISTINCT FROM NEW.student_id THEN PERFORM finance.historical_mark(OLD.student_id); END IF;
    END IF;
    RETURN NEW;
END $function$;
COMMENT ON FUNCTION finance.trg_historical_graduand() IS
  'V723: an approved award — given, withdrawn, or moved to another session or record — marks the student''s historical summary stale (or removes it, when the student leaves the population); an entry awaiting the Senate changes nothing.';
DROP TRIGGER IF EXISTS trg_historical_graduand ON records.graduand;
CREATE TRIGGER trg_historical_graduand AFTER INSERT OR DELETE OR UPDATE OF senate_state, session, student_id ON records.graduand
    FOR EACH ROW EXECUTE FUNCTION finance.trg_historical_graduand();

-- a calendar's move: when the University's (or the School's, or the Centre's) current session changes, the past of every student
-- studying under it ends one session later or earlier — each of them is marked stale and worked out by the desk's next reads
CREATE TABLE finance.historical_bound (
    stream text PRIMARY KEY CHECK (stream IN ('UG', 'PG', 'CCE')),
    last_session text,
    moved_at timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE finance.historical_bound IS
  'V723: the end of a studying student''s past on each calendar (the session before its current one) as last seen — a move marks that calendar''s studying students stale.';
SELECT audit.exempt('finance.historical_bound', 'V723: the last end of the past seen on each calendar, kept to notice a move; worked out, never decided by a person');
INSERT INTO finance.historical_bound (stream, last_session) VALUES
    ('UG', finance.session_before(policy.university_current_session())),
    ('PG', finance.session_before(coalesce((SELECT a.name FROM admissions.pg_academic_session a WHERE a.state = 'CURRENT' ORDER BY a.name DESC LIMIT 1),
                                           policy.university_current_session()))),
    ('CCE', finance.session_before(coalesce(policy.route_session('CCE'), policy.university_current_session())));

CREATE OR REPLACE FUNCTION finance.historical_bounds_moved() RETURNS integer LANGUAGE plpgsql AS $function$
DECLARE v_moved text[]; n int := 0;
BEGIN
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
    IF v_moved IS NULL THEN RETURN 0; END IF;
    -- the students whose past ends on a calendar: studying (ACTIVE, PROBATION), no award approved — the population's part bounded by it
    INSERT INTO finance.historical_stale (student_id)
    SELECT s.id FROM people.student s
     WHERE s.status IN ('ACTIVE', 'PROBATION') AND s.entry_session IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = s.id AND g.senate_state = 'APPROVED')
       AND (CASE WHEN s.entry_mode = 'CCE' THEN 'CCE' WHEN s.entry_mode = 'POSTGRADUATE' THEN 'PG' ELSE 'UG' END) = ANY (v_moved)
    ON CONFLICT (student_id) DO UPDATE SET marked_at = now();
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $function$;
COMMENT ON FUNCTION finance.historical_bounds_moved() IS
  'V723: whether the end of a studying student''s past moved on any calendar since last seen; if so, that calendar''s studying students are marked stale (the desk works them out 500 a read, or the Bursar''s full refresh at once). Returns the students marked.';

CREATE OR REPLACE FUNCTION finance.trg_historical_bounds() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
    PERFORM finance.historical_bounds_moved();
    RETURN NULL;
END $function$;
DROP TRIGGER IF EXISTS trg_historical_bounds ON policy.academic_session;
CREATE TRIGGER trg_historical_bounds AFTER INSERT OR UPDATE OR DELETE ON policy.academic_session
    FOR EACH STATEMENT EXECUTE FUNCTION finance.trg_historical_bounds();
DROP TRIGGER IF EXISTS trg_historical_bounds ON admissions.pg_academic_session;
CREATE TRIGGER trg_historical_bounds AFTER INSERT OR UPDATE OR DELETE ON admissions.pg_academic_session
    FOR EACH STATEMENT EXECUTE FUNCTION finance.trg_historical_bounds();
DROP TRIGGER IF EXISTS trg_historical_bounds ON policy.study_route;
CREATE TRIGGER trg_historical_bounds AFTER UPDATE ON policy.study_route
    FOR EACH STATEMENT EXECUTE FUNCTION finance.trg_historical_bounds();

-- ── 3 · once: summaries and marks outside the population removed; the postgraduate population marked stale for the new bound ──
DELETE FROM finance.historical_stale x USING people.student s WHERE s.id = x.student_id AND NOT finance.historical_population(s.status, s.id, s.entry_session);
DELETE FROM finance.historical_summary h USING people.student s WHERE s.id = h.student_id AND NOT finance.historical_population(s.status, s.id, s.entry_session);
INSERT INTO finance.historical_stale (student_id)
SELECT s.id FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
 WHERE people.is_postgraduate(s.entry_mode, p.category) AND finance.historical_population(s.status, s.id, s.entry_session)
ON CONFLICT (student_id) DO NOTHING;

COMMIT;
