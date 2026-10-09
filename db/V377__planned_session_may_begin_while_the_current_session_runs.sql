-- V377: a planned session may begin while the current session is still running.
--
-- The University starts its next session before the last one ends: 2026/2027 may begin (its entrants admitted, its
-- semester dated, its fees stated) while 2025/2026 is still finishing for its returning students. Since V013 the
-- calendar refused that — no two sessions might overlap (ex_session_no_overlap) — so a planned session could not be
-- dated to begin inside the current one, nor the current one's end moved past the planned one's beginning.
--
-- The rule is released. What stays:
--   * one session is CURRENT at a time (uq_session_one_current), and only on its Senate minute;
--   * the transition (V289) makes a planned session current only when it begins after the current one began — the order
--     of sessions is the order of the days they begin, so no two sessions (other than a cancelled one) begin on the same
--     day (SESSION_SAME_START), which keeps "the next planned session" one session;
--   * the transition still completes the current session in the same transaction; it may now happen before the current
--     session's end date, and the readiness check says so.
-- Nothing reads a session from a date alone: the code that does so prefers the CURRENT session first (V289) or a session
-- the row names, so two sessions holding the same day change no answer.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V377: a planned session may begin while the current session runs', true);

-- ── 1 · sessions may overlap ──────────────────────────────────────────────────────────────────────────────────────
ALTER TABLE policy.academic_session DROP CONSTRAINT IF EXISTS ex_session_no_overlap;

-- ── 2 · but no two begin on the same day ─────────────────────────────────────────────────────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS uq_session_starts_on ON policy.academic_session (starts_on) WHERE state <> 'CANCELLED';

CREATE OR REPLACE FUNCTION policy.session_same_start()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE other text;
BEGIN
    IF NEW.state = 'CANCELLED' THEN RETURN NEW; END IF;
    SELECT s.name INTO other FROM policy.academic_session s
     WHERE s.starts_on = NEW.starts_on AND s.name <> NEW.name AND s.state <> 'CANCELLED' LIMIT 1;
    IF other IS NOT NULL THEN
        RAISE EXCEPTION 'SESSION_SAME_START: % cannot begin on %, the day % begins; sessions follow one another by the day they begin, so give it another day',
            NEW.name, to_char(NEW.starts_on, 'FMDD Mon YYYY'), other USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END $fn$;

DROP TRIGGER IF EXISTS trg_session_same_start ON policy.academic_session;
CREATE TRIGGER trg_session_same_start BEFORE INSERT OR UPDATE OF starts_on, state ON policy.academic_session
    FOR EACH ROW EXECUTE FUNCTION policy.session_same_start();

COMMENT ON INDEX policy.uq_session_starts_on IS
  'No two sessions (other than a cancelled one) begin on the same day (V377): sessions may overlap, and follow one another by the day they begin.';

-- ── 3 · the transition's check says when the planned session began inside the current one ─────────────────────────
CREATE OR REPLACE FUNCTION policy.transition_readiness(p_to text)
RETURNS TABLE(code text, ok boolean, blocking boolean, detail text)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE s policy.academic_session%ROWTYPE; cur policy.academic_session%ROWTYPE; n_sem int; n_dated int; n_fee int; n_fresh int; n_win int;
BEGIN
    SELECT * INTO s FROM policy.academic_session WHERE name = p_to;
    SELECT * INTO cur FROM policy.academic_session WHERE state = 'CURRENT';
    IF s.name IS NULL THEN
        RETURN QUERY SELECT 'SESSION_EXISTS', false, true, 'No session named ' || coalesce(p_to, '?') || ' is on the calendar.';
        RETURN;
    END IF;
    RETURN QUERY SELECT 'SESSION_EXISTS', true, true, p_to || ' is on the calendar (' || policy.session_label(s.state) || ').';
    RETURN QUERY SELECT 'STATE_PLANNED', s.state = 'PLANNED', true,
        CASE s.state WHEN 'PLANNED' THEN 'The session is planned.'
                     WHEN 'CURRENT' THEN 'The session is already current; nothing is to be done.'
                     WHEN 'DRAFT' THEN 'The session is still a draft: mark it planned once its setup is agreed.'
                     ELSE 'The session is ' || lower(policy.session_label(s.state)) || ' and cannot become current again.' END;
    RETURN QUERY SELECT 'SENATE_MINUTE', s.senate_minute IS NOT NULL AND btrim(s.senate_minute) <> '', true,
        CASE WHEN s.senate_minute IS NOT NULL AND btrim(s.senate_minute) <> '' THEN 'Senate minute ' || s.senate_minute || ' is recorded.'
             ELSE 'No Senate minute is recorded against the session; a session is not current without the minute that resolved to run it.' END;
    RETURN QUERY SELECT 'NO_CONFLICT', cur.name IS NULL OR cur.name = s.name OR s.starts_on > cur.starts_on, true,
        CASE WHEN cur.name IS NULL THEN 'No session is current; ' || p_to || ' becomes the first.'
             WHEN cur.name = s.name THEN 'Already the current session.'
             -- V377: the planned session may have begun while the current one runs; the transition completes it all the same
             WHEN s.starts_on > cur.starts_on AND s.starts_on <= cur.ends_on
                 THEN p_to || ' began on ' || to_char(s.starts_on, 'FMDD Mon YYYY') || ', while ' || cur.name || ' runs to '
                      || to_char(cur.ends_on, 'FMDD Mon YYYY') || '; the transition completes ' || cur.name || ' from then, and its records stay as they are.'
             WHEN s.starts_on > cur.starts_on THEN cur.name || ' is current and will be completed by the transition.'
             ELSE p_to || ' begins before the current session ' || cur.name || ' and cannot follow it.' END;
    SELECT count(*), count(*) FILTER (WHERE lectures_from IS NOT NULL) INTO n_sem, n_dated FROM policy.semester WHERE session = p_to;
    RETURN QUERY SELECT 'SEMESTERS_CONFIGURED', n_sem >= 1, false,
        CASE WHEN n_sem >= s.semesters THEN n_sem || ' of ' || s.semesters || ' semesters are on the calendar.'
             WHEN n_sem >= 1 THEN n_sem || ' of ' || s.semesters || ' semesters are on the calendar; the rest can follow.'
             ELSE 'No semester of ' || p_to || ' is on the calendar yet.' END;
    RETURN QUERY SELECT 'FIRST_SEMESTER_DATED', EXISTS (SELECT 1 FROM policy.semester WHERE session = p_to AND number = 1 AND lectures_from IS NOT NULL), false,
        CASE WHEN EXISTS (SELECT 1 FROM policy.semester WHERE session = p_to AND number = 1 AND lectures_from IS NOT NULL)
             THEN 'The first semester''s lectures are dated.' ELSE 'The first semester has no lecture dates; registration, examinations and results wait on them.' END;
    SELECT count(*) INTO n_fee FROM finance.fee_schedule WHERE session = p_to AND ended_at IS NULL;
    RETURN QUERY SELECT 'FEE_SCHEDULE', n_fee > 0, false,
        CASE WHEN n_fee > 0 THEN n_fee || ' fee schedule line(s) are stated for ' || p_to || '.' ELSE 'The Bursar has stated no fee schedule for ' || p_to || '; students see no charge.' END;
    SELECT count(*) INTO n_win FROM policy.portal_window WHERE session = p_to AND superseded_at IS NULL;
    RETURN QUERY SELECT 'PORTAL_WINDOWS', true, false,
        CASE WHEN n_win > 0 THEN n_win || ' portal window rule(s) are set for ' || p_to || '.' ELSE 'No portal window is configured for ' || p_to || '; school fees payment and course registration are open by default.' END;
    SELECT count(*) INTO n_fresh FROM people.student WHERE entry_session = p_to;
    RETURN QUERY SELECT 'FRESH_STUDENTS', true, false,
        CASE WHEN n_fresh > 0 THEN n_fresh || ' entrant(s) of ' || p_to || ' are on the register and continue under the same accounts.' ELSE 'No entrant of ' || p_to || ' is on the register yet.' END;
    RETURN QUERY SELECT 'RETURNING_STUDENTS', true, false,
        'Returning students are not moved by the transition: they progress by the results, promotion and roll-over rules that already exist.';
END $fn$;

COMMENT ON FUNCTION policy.transition_readiness(text) IS
  'The checks the transition into a planned session runs (V289): blocking ones stop it (exists, planned, Senate minute, begins after the current session began); advisory ones are shown and, for the automatic clock, also block. Since V377 the planned session may begin before the current one ends.';

COMMENT ON TABLE policy.academic_session IS
  'The academic calendar''s sessions: DRAFT, PLANNED, CURRENT (one at a time, on its Senate minute), CLOSED (Completed), ARCHIVED, CANCELLED. Sessions may overlap since V377 — the next may begin while the current one runs — and no two begin on the same day.';

COMMIT;
