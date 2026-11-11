-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  V720 · Outstanding school fees of past sessions are shown to, and paid by, every student — undergraduate and postgraduate,
--         studying or graduated
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════
--  The University's brief of 11 November 2026 ("Undergraduate and postgraduate outstanding school fees detection, dashboard display
--  and payment"): the portal detects what a student still owes from past sessions and semesters, but the dashboards did not show it,
--  least of all to graduates, and a student still studying could not pay it. Read against what stood:
--
--    · The detection engine is finance.historical_rows_read / historical_rows / historical_account (V654, V665, V683, V693): every
--      session of the record from the assessment start, assessed as the student was then (an approved assessment, else the session's
--      lines at the session's level — a postgraduate student's stage lines — else for review), the session's payments allocated
--      first semester first, waivers netted. It reads any student, undergraduate or postgraduate, studying or graduated, and it is
--      right for every one of the brief's cases; it is NOT rebuilt here.
--    · finance.position (V033…V616) reads a session's lines for the student as they are NOW — the level today — right for the
--      current session and wrong for a past one (the V654 note says so), so a 300 Level student owing their 100 Level session read
--      "nothing due" for it on the fees page.
--
--  What was wrong, and what this migration changes:
--    1 · finance.historical_reference refused anyone not graduated (HFA_PAY_GRADUATES, "a student still studying pays from the
--        fees page") — but the fees page prices a past session at today's level and behind that session's payment window, so a
--        student still studying had no door for a closed session's balance. The door now opens for every student whose historical
--        account lists the session owed (by construction only sessions before the student's current one): online payment on,
--        something owed, never more than owed. An open, unexpired reference for the same session and amount is handed back rather
--        than a second one minted (a double click, a refreshed page).
--    2 · The summary behind every desk list, tile and report (finance.historical_summary) was worked out for graduates only, so a
--        student still studying with a past-session balance was on no list. finance.historical_refresh and historical_refresh_stale
--        now cover every student studying (ACTIVE, PROBATION), graduated, or an approved graduand (finance.historical_population),
--        the payment trigger marks any of them stale, and the summary carries two counts the desk filters on: the sessions owed in
--        whole (nothing of the session paid) and in part. The migration works the whole population out once, in batches.
--    3 · A student's "past" ended before the University's current session whatever their calendar: a postgraduate student's own
--        current session (the School's) could be read as history, or their last finished one left out, when the two calendars
--        differ. The bound is now the student's own calendar, as people.student_current_session reads it (finance.session_before).
--    4 · The School of Postgraduate Studies (pgschool, pgsecretary) reads the historical desk for postgraduate students.
--  The dashboards, the fees page, the student's one outstanding-fees read and the desk's filters are the API's and the screens'.
-- ════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════════

BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'bursar', true),
       set_config('moaum.reason', 'V720: outstanding school fees of past sessions shown to and paid by every student (the University''s brief of 11 November 2026)', true);

-- ── 1 · the session before a calendar's current one; the population the summary is kept for ─────────────────────────────────
CREATE OR REPLACE FUNCTION finance.session_before(p_current text) RETURNS text LANGUAGE sql STABLE AS $$
    SELECT max(a.name) FROM policy.academic_session a
     WHERE a.state NOT IN ('CANCELLED', 'DRAFT') AND a.name < coalesce(p_current, '9999/9999')
$$;
COMMENT ON FUNCTION finance.session_before(text) IS
  'V720: the last session on the calendar before the one given (cancelled and draft sessions aside) — the end of a student''s past when the one given is their current session.';

CREATE OR REPLACE FUNCTION finance.historical_population(p_status text, p_student uuid, p_entry_session text) RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT p_entry_session IS NOT NULL
       AND (p_status IN ('ACTIVE', 'PROBATION', 'GRADUATED')
            OR EXISTS (SELECT 1 FROM records.graduand g WHERE g.student_id = p_student AND g.senate_state = 'APPROVED'))
$$;
COMMENT ON FUNCTION finance.historical_population(text, uuid, text) IS
  'V720: whether a student''s historical summary is kept — studying (ACTIVE, PROBATION), graduated, or an approved graduand, with an entry session on the record. Any student''s account is still read live.';

-- ── 2 · the engine: a student's past ends before their own calendar's current session ──────────────────────────────────────
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
                                   finance.session_before(coalesce(admissions.pg_current_session(), policy.university_current_session())) AS before_pg,
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
                    ELSE CASE WHEN s.entry_mode = 'CCE' THEN b.before_cce WHEN s.entry_mode = 'POSTGRADUATE' THEN b.before_pg ELSE b.before_current END END AS last_session
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
  'V654, V665, V693, V720: a student''s historical account read set-based — every session from the assessment start to the graduation session (a graduate) or to the session before the student''s own calendar''s current one (a student studying: the University''s, the School of Postgraduate Studies'' or the Centre''s), each semester assessed as the student was then, payments allocated first semester first, waivers netted.';

-- ── 3 · the summary: every student studying or graduated, with the sessions owed in whole and in part ─────────────────────
ALTER TABLE finance.historical_summary ADD COLUMN whole_sessions integer NOT NULL DEFAULT 0, ADD COLUMN part_sessions integer NOT NULL DEFAULT 0;
COMMENT ON COLUMN finance.historical_summary.whole_sessions IS 'V720: sessions of the account owed in whole — something assessed, nothing of the session paid';
COMMENT ON COLUMN finance.historical_summary.part_sessions IS 'V720: sessions of the account owed in part — something paid, a balance left';

CREATE OR REPLACE FUNCTION finance.historical_refresh(p_students uuid[] DEFAULT NULL::uuid[])
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE v_ids uuid[]; n int;
BEGIN
    -- V720: every student the historical account is read for — studying, on probation or graduated (and an approved graduand)
    v_ids := coalesce(p_students, (SELECT array_agg(s.id) FROM people.student s WHERE finance.historical_population(s.status, s.id, s.entry_session)));
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
  'V654, V665, V720: the historical summary of the students given — or, given none, of every student studying, graduated or an approved graduand (finance.historical_population) — worked out again from finance.historical_rows; the sessions owed in whole and in part counted; the stale marks cleared.';

CREATE OR REPLACE FUNCTION finance.historical_refresh_stale(p_limit integer DEFAULT 500)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
DECLARE v_ids uuid[]; v_new uuid[]; v_lim int := greatest(p_limit, 1);
BEGIN
    SELECT array_agg(x.student_id) INTO v_ids
      FROM (SELECT h.student_id FROM finance.historical_stale h ORDER BY h.marked_at LIMIT v_lim FOR UPDATE SKIP LOCKED) x;
    IF coalesce(cardinality(v_ids), 0) < v_lim THEN
        -- V720: a student of the population with no summary yet — newly graduated, newly admitted a session ago, or never worked out
        SELECT array_agg(n.id) INTO v_new
          FROM (SELECT s.id FROM people.student s
                 WHERE finance.historical_population(s.status, s.id, s.entry_session)
                   AND NOT EXISTS (SELECT 1 FROM finance.historical_summary h WHERE h.student_id = s.id)
                   AND s.id <> ALL (coalesce(v_ids, '{}'::uuid[]))
                 LIMIT v_lim - coalesce(cardinality(v_ids), 0)) n;
        v_ids := coalesce(v_ids, '{}'::uuid[]) || coalesce(v_new, '{}'::uuid[]);
    END IF;
    IF cardinality(v_ids) = 0 THEN RETURN 0; END IF;
    RETURN finance.historical_refresh(v_ids);
END $function$;
COMMENT ON FUNCTION finance.historical_refresh_stale(integer) IS
  'V654, V720: the summaries marked stale worked out again, up to the limit, then students of the population with no summary yet; called before every desk read.';

CREATE OR REPLACE FUNCTION finance.trg_historical_stale_payment() RETURNS trigger LANGUAGE plpgsql AS $function$
BEGIN
    -- V720: a school-fee payment marks its student stale whether or not a summary exists yet (a student studying had none)
    IF NEW.student_id IS NOT NULL AND NEW.purpose LIKE 'School fees%' THEN
        INSERT INTO finance.historical_stale (student_id) VALUES (NEW.student_id) ON CONFLICT (student_id) DO NOTHING;
    END IF;
    RETURN NEW;
END $function$;

-- ── 4 · the pay door: every student whose account lists the session owed ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION finance.historical_reference(p_student uuid, p_session text, p_amount numeric)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE v_owed numeric; v_ref text; v_matric text; v_open text;
BEGIN
    IF NOT coalesce((SELECT s.online_payment FROM finance.historical_setting s WHERE s.id = 1), false) THEN
        RAISE EXCEPTION 'HFA_ONLINE_OFF: historical school fees are settled with the Bursary' USING ERRCODE = '23514';
    END IF;
    SELECT coalesce(s.matric_no, s.admission_no, 'X') INTO v_matric FROM people.student s WHERE s.id = p_student;
    IF v_matric IS NULL THEN RAISE EXCEPTION 'no such student' USING ERRCODE = '23503'; END IF;
    -- V720: the session must be on the student's historical account with a balance — a past session of their own calendar, whoever
    -- they are; the current session is paid on the fees page (it is not on the account)
    SELECT sum(x.outstanding) INTO v_owed FROM finance.historical_account(p_student) x WHERE x.session = p_session AND x.outstanding > 0;
    IF coalesce(v_owed, 0) <= 0 THEN
        RAISE EXCEPTION 'HFA_NOTHING_OWED: nothing is owed for % on the historical account', p_session USING ERRCODE = '23514',
            HINT = 'A past session with a balance is paid here; this session''s school fees are paid on the fees page.';
    END IF;
    IF p_amount IS NULL OR p_amount <= 0 OR p_amount > v_owed THEN
        RAISE EXCEPTION 'HFA_PAY_AMOUNT: pay up to % for %, the balance owed', to_char(v_owed, 'FM999,999,999,990.00'), p_session USING ERRCODE = '23514';
    END IF;
    -- V720: an open, unexpired reference for the same session and amount is the one to pay, never a second
    SELECT r.reference INTO v_open FROM finance.payment_reference r
     WHERE r.student_id = p_student AND r.session = p_session AND r.purpose = 'School fees ' || p_session || ' (historical)'
       AND r.confirmed_at IS NULL AND r.archived_at IS NULL AND r.expires_at > now() AND r.amount = p_amount
     ORDER BY r.generated_at DESC LIMIT 1;
    IF v_open IS NOT NULL THEN RETURN v_open; END IF;
    FOR v_try IN 1..50 LOOP
        v_ref := 'MOAUM-FEE-' || regexp_replace(right(v_matric, 7), '[^0-9A-Z]', '', 'g') || '-' || lpad((floor(random() * 10000))::int::text, 4, '0');
        INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at)
        VALUES (p_student, p_session, v_ref, 'School fees ' || p_session || ' (historical)', p_amount, now() + interval '24 hours')
        ON CONFLICT (reference) DO NOTHING;
        IF FOUND THEN RETURN v_ref; END IF;
    END LOOP;
    RAISE EXCEPTION 'FEE_REFERENCE_EXHAUSTED: no free payment reference was found for % in fifty draws', v_matric USING ERRCODE = '23514';
END $function$;
COMMENT ON FUNCTION finance.historical_reference(uuid, text, numeric) IS
  'V654, V720: a payment reference for a past session''s balance on the student''s historical account — any student, studying or graduated — up to the balance owed, while online payment is on; an open reference for the same session and amount is returned rather than another made.';

-- ── 5 · the School of Postgraduate Studies reads the desk for its students ────────────────────────────────────────────────
INSERT INTO finance.historical_grant (office_code, permission)
SELECT o, p FROM (VALUES ('pgschool'), ('pgsecretary')) x(o)
 CROSS JOIN (VALUES ('VIEW_HISTORICAL_FEE_ASSESSMENT'), ('VIEW_HISTORICAL_FEE_REPORT'), ('VIEW_HISTORICAL_PAYMENT'),
                    ('VIEW_ASSESSMENT_HISTORY'), ('VIEW_FINANCIAL_CLEARANCE')) y(p)
 WHERE EXISTS (SELECT 1 FROM ref.office WHERE code = x.o)
ON CONFLICT DO NOTHING;

-- ── 6 · the population worked out once, in batches ───────────────────────────────────────────────────────────────────────
DO $$
DECLARE v_batch uuid[]; n int := 0; t0 timestamptz := clock_timestamp();
BEGIN
    FOR v_batch IN
        SELECT array_agg(s.id) FROM (SELECT s.id, (row_number() OVER (ORDER BY s.id) - 1) / 2000 AS b FROM people.student s
                                      WHERE finance.historical_population(s.status, s.id, s.entry_session)) s GROUP BY s.b ORDER BY s.b
    LOOP
        n := n + finance.historical_refresh(v_batch);
    END LOOP;
    UPDATE finance.historical_setting SET refreshed_at = now() WHERE id = 1;
    RAISE NOTICE 'V720: % historical summaries worked out in %', n, clock_timestamp() - t0;
END $$;

COMMIT;
