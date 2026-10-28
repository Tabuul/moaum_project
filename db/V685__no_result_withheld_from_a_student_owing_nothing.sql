-- ════════════════════════════════════════════════════════════════════════
--  V685 · No result withheld from a student who owes nothing
-- ════════════════════════════════════════════════════════════════════════
--  The University's word of 28 October 2026, on a 300 Level B.A. English student's Result Broadsheet ("Results of 2 semesters are
--  withheld until their school fees are paid — Withheld: 2023/2024 first semester; 2023/2024 second semester", with no amount
--  outstanding named): "allow all the students that are not owing fee to view their results, no restriction for viewing of result
--  if the student is not owing anything".
--
--  The cause. V667's finance.results_cleared withheld a semester (1) wherever the session's fees were not stated for the student, and
--  otherwise (2) where the fees up to the semester were not paid — both read through finance.fee_stated, finance.due_for_semester and
--  finance.position, which match the fee lines to the student's CURRENT level (V654's warning: never read a past session through them).
--  While the fee setup held 2025/2026 alone, an earlier session counted as "before the schedule" (finance.schedule_from) and was
--  released. Once an earlier session's structure is on the setup (the historical school fees, V654), a 300 Level student entered in
--  2023/2024 is matched to 2023/2024's 300 Level lines: none → "not stated" → withheld though nothing is owed (the screenshot's case:
--  no amount named); or a 300 Level line → owing the wrong year's fee.
--
--  Now a semester's results are withheld only where the student owes:
--  · finance.results_outstanding(student, session, semester): a session before the student's current one is read from the historical
--    account (finance.historical_rows, V654/V665: the session's lines as the student was then — the level of that session — or an
--    approved assessment, waivers netted off, payments allocated first semester first), the outstanding of the semester and those before
--    it; nothing assessed (before the Bursar's start, or awaiting review) is nothing owed. The current session (or a later one) as
--    before: its lines at the student's level against its confirmed school-fee payments (not archived), short by under one naira paid.
--  · finance.results_arrears(student, session): a balance owed for a session before this one — the historical account for the sessions
--    before the student's current one; for a session from the current one on, its lines against its payments.
--  · finance.results_cleared restated: never gated → released; for the current session, its RESULTS rule met → released (as V667;
--    a past session is not read through the rule, which matches the lines to today's level); a balance owed
--    for an earlier session blocks where the Bursar's scheme says arrears block everything (as V667, now read from the account);
--    otherwise released exactly when nothing is outstanding up to the semester. "Fees not stated" no longer withholds anything.
--  The withheld semester is named with finance.results_outstanding (StudentPortalRepository.semesterOutstanding). Nothing on record
--  changes; the gates of course registration, examinations and the fees page are untouched.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION finance.results_outstanding(p_student uuid, p_session text, p_semester integer)
RETURNS numeric LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_cur text := coalesce(people.student_current_session(p_student), policy.university_current_session());
        v_due numeric; v_paid numeric;
BEGIN
    -- a past session: the historical account, at the level the student was in that session
    IF v_cur IS NOT NULL AND p_session < v_cur THEN
        RETURN coalesce((SELECT sum(greatest(x.outstanding, 0)) FROM finance.historical_rows(ARRAY[p_student]) x
                          WHERE x.session = p_session AND x.semester <= p_semester), 0);
    END IF;
    -- the current session (or a later one): its lines and its confirmed school-fee payments, as V667 read them
    v_due := finance.due_for_semester(p_student, p_session, p_semester);
    v_paid := coalesce((SELECT sum(r.amount) FROM finance.payment_reference r
                         WHERE r.student_id = p_student AND r.session = p_session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
                           AND r.purpose LIKE 'School fees%'), 0);
    RETURN CASE WHEN finance.fee_short(v_due, v_paid) THEN v_due - v_paid ELSE 0 END;
END $fn$;
COMMENT ON FUNCTION finance.results_outstanding(uuid, text, integer) IS
  'V685: what a student owes for a semester''s results — a session before the student''s current one from the historical account (finance.historical_rows: the level of that session, an approved assessment, waivers, payments first semester first), the semester and those before it; the current session from its lines against its confirmed school-fee payments; 0 where nothing is owed or nothing is assessed.';

CREATE OR REPLACE FUNCTION finance.results_arrears(p_student uuid, p_session text)
RETURNS boolean LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_cur text := coalesce(people.student_current_session(p_student), policy.university_current_session());
BEGIN
    -- the sessions before the student's current one: the historical account
    IF EXISTS (SELECT 1 FROM finance.historical_rows(ARRAY[p_student]) x
                WHERE x.session < p_session AND (v_cur IS NULL OR x.session < v_cur) AND x.outstanding > 0) THEN
        RETURN true;
    END IF;
    -- a session from the current one up to this one: its lines (at the level the student is at now, which is that session's) and payments
    RETURN EXISTS (
        SELECT 1
          FROM (SELECT DISTINCT f.session FROM finance.fee_schedule f
                 WHERE f.session < p_session AND f.ended_at IS NULL AND (v_cur IS NULL OR f.session >= v_cur)) s
         WHERE finance.fee_short((SELECT coalesce(sum(c.amount), 0) FROM finance.charges(p_student, s.session) c),
                                 (SELECT coalesce(sum(r.amount), 0) FROM finance.payment_reference r
                                   WHERE r.student_id = p_student AND r.session = s.session AND r.confirmed_at IS NOT NULL AND r.archived_at IS NULL
                                     AND r.purpose LIKE 'School fees%')));
END $fn$;
COMMENT ON FUNCTION finance.results_arrears(uuid, text) IS
  'V685: whether the student owes for a session before this one — the historical account for the sessions before their current one, the lines against the payments for a session from the current one on.';

CREATE OR REPLACE FUNCTION finance.results_cleared(p_student uuid, p_session text, p_semester integer)
RETURNS boolean LANGUAGE plpgsql STABLE AS $fn$
DECLARE v_releases text; v_block boolean; v_cur text := coalesce(people.student_current_session(p_student), policy.university_current_session());
BEGIN
    SELECT r.releases_at, s.arrears_block_all INTO v_releases, v_block
      FROM policy.clearance_rule r JOIN policy.clearance_scheme s ON s.version_id = r.version_id
     WHERE r.version_id = policy.in_force('clearance', 'UNIVERSITY', current_date) AND r.purpose = 'RESULTS';
    IF v_releases = 'NEVER_GATED' THEN RETURN true; END IF;
    -- the current session's own rule, as before (a past session is not read through it: it matches the lines to today's level)
    IF NOT (v_cur IS NOT NULL AND p_session < v_cur) AND finance.clears(p_student, p_session, 'RESULTS') THEN RETURN true; END IF;
    -- a balance owed for an earlier session blocks everything where the Bursar's scheme says so, as before — now read from the account
    IF coalesce(v_block, false) AND finance.results_arrears(p_student, p_session) THEN RETURN false; END IF;
    -- V685: otherwise released exactly when nothing is outstanding up to the semester; fees not stated owe nothing
    RETURN finance.results_outstanding(p_student, p_session, p_semester) <= 0;
END $fn$;
COMMENT ON FUNCTION finance.results_cleared(uuid, text, integer) IS
  'V667, V685: whether a semester''s results are released to the student — never gated, or (the current session) its RESULTS rule met (finance.clears), or else nothing outstanding up to that semester (finance.results_outstanding: a past session from the historical account, at the level of that session), unless a balance owed for an earlier session blocks everything (arrears_block_all, finance.results_arrears). A student who owes nothing has nothing withheld; fees not stated owe nothing.';

COMMIT;
