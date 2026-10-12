-- ═══════════════════════════════════════
-- V400 — overlapping sessions, followed up
--
--   V377 let the next session begin while the current one runs. Three things followed from that and are done here:
--     1 · the session current on a day. A payment imported from the old portal with no session of its own was matched to
--         the session its date fell in; inside an overlap two sessions hold the day. policy.session_current_on(day) answers
--         with the session that was current that day — by the transition log (V289) where one is kept, else the session that
--         was already running (the earliest to begin that holds the day); finance.legacy_nelfund_stage reads it.
--     2 · the transition checks say what is still open in the session being completed — open semesters, score sheets not yet
--         published, registrations awaiting approval — for the Registry to know; informative, never blocking, since those
--         are completed in their own time and the transition does not close them.
--     3 · a reminder. Once the current session's end date has passed and it is still current, the Registry, the Academic
--         Office and the Directorate of ICT are told once a day, by the session clock (policy.remind_session_overrun says
--         what to tell and keeps the day's row in policy.session_overrun_notice, so nothing is said twice in a day).
-- ═══════════════════════════════════════
BEGIN;
SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true),
       set_config('moaum.actor_office', 'ict', true),
       set_config('moaum.reason', 'V400: overlapping sessions followed up', true);

-- ── 1 · the session current on a day ────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION policy.session_current_on(p_day date)
RETURNS text LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(
        (SELECT t.to_session FROM policy.session_transition t
          WHERE t.outcome = 'DONE' AND (t.at AT TIME ZONE 'Africa/Lagos')::date <= p_day
          ORDER BY t.at DESC LIMIT 1),
        (SELECT a.name FROM policy.academic_session a
          WHERE p_day BETWEEN a.starts_on AND a.ends_on AND a.state <> 'CANCELLED'
          ORDER BY a.starts_on LIMIT 1))
$fn$;
COMMENT ON FUNCTION policy.session_current_on(date) IS
  'V400: the session that was current on a day — the last transition logged on or before it (V289), else the session already running that holds the day (two sessions may overlap since V377).';

-- ── 3 · the reminder once the current session has run past its end date ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS policy.session_overrun_notice (
    session text NOT NULL REFERENCES policy.academic_session(name) ON DELETE CASCADE ON UPDATE CASCADE,
    told_on date NOT NULL,
    PRIMARY KEY (session, told_on)
);
COMMENT ON TABLE policy.session_overrun_notice IS
  'V400: the days on which the offices were reminded that the current session has run past its end date — one reminder a day.';
SELECT audit.attach('policy.session_overrun_notice') WHERE NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_audit_policy_session_overrun_notice');

CREATE OR REPLACE FUNCTION policy.remind_session_overrun()
RETURNS TABLE(session text, ends_on date, days_over int, next_planned text, subject text, body text)
LANGUAGE plpgsql AS $fn$
DECLARE cur policy.academic_session; nxt text; d int;
BEGIN
    SELECT * INTO cur FROM policy.academic_session a WHERE a.state = 'CURRENT';
    IF cur.name IS NULL OR cur.ends_on >= current_date THEN RETURN; END IF;
    IF EXISTS (SELECT 1 FROM policy.session_overrun_notice n WHERE n.session = cur.name AND n.told_on = current_date) THEN RETURN; END IF;
    INSERT INTO policy.session_overrun_notice (session, told_on) VALUES (cur.name, current_date);
    nxt := policy.next_planned_session();
    d := current_date - cur.ends_on;
    RETURN QUERY SELECT cur.name, cur.ends_on, d, nxt,
        'Academic session ' || cur.name || ' is still current ' || d || ' day' || CASE WHEN d = 1 THEN '' ELSE 's' END || ' after its end date',
        cur.name || ' ended on ' || to_char(cur.ends_on, 'FMDD Mon YYYY') || ' and is still the current session. '
        || CASE WHEN nxt IS NULL THEN 'No session is planned after it: plan the next session on the calendar, then transition into it. '
                ELSE nxt || ' is planned after it: transition into ' || nxt || ' from the calendar, or set its automatic transition date. ' END
        || 'Until then every desk that works to the current session works to ' || cur.name || '.';
END $fn$;
COMMENT ON FUNCTION policy.remind_session_overrun() IS
  'V400: what the offices are told once the current session has run past its end date — one row a day while it stands, none otherwise; the session clock sends it.';

-- ── 2 · the transition checks name what is still open in the completing session ──────────────────────────────────
CREATE OR REPLACE FUNCTION policy.transition_readiness(p_to text)
 RETURNS TABLE(code text, ok boolean, blocking boolean, detail text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s policy.academic_session%ROWTYPE; cur policy.academic_session%ROWTYPE; n_sem int; n_dated int; n_fee int; n_fresh int; n_win int; n_cur_sem int; n_cur_sheets int; n_cur_regs int;
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
    -- V400: what is still open in the session the transition completes — said, never blocking: it is completed in its own time
    IF cur.name IS NOT NULL AND cur.name <> s.name THEN
        SELECT count(*) INTO n_cur_sem FROM policy.semester WHERE session = cur.name AND state = 'OPEN';
        RETURN QUERY SELECT 'CURRENT_SEMESTERS_OPEN', true, false,
            CASE WHEN n_cur_sem = 0 THEN 'No semester of ' || cur.name || ' is open.'
                 ELSE n_cur_sem || ' semester' || CASE WHEN n_cur_sem = 1 THEN '' ELSE 's' END || ' of ' || cur.name || ' still open; the transition does not close them.' END;
        SELECT count(*) INTO n_cur_sheets FROM assessment.score_sheet sh JOIN catalogue.offering o ON o.id = sh.offering_id
         WHERE o.session = cur.name AND sh.stage <> 'PUBLISHED';
        RETURN QUERY SELECT 'CURRENT_SHEETS_PENDING', true, false,
            CASE WHEN n_cur_sheets = 0 THEN 'Every score sheet of ' || cur.name || ' is published.'
                 ELSE n_cur_sheets || ' score sheet' || CASE WHEN n_cur_sheets = 1 THEN '' ELSE 's' END || ' of ' || cur.name || ' not yet published; they go on through the chain as before.' END;
        SELECT count(*) INTO n_cur_regs FROM registration.course_registration WHERE session = cur.name AND status = 'SUBMITTED';
        RETURN QUERY SELECT 'CURRENT_REGISTRATIONS_PENDING', true, false,
            CASE WHEN n_cur_regs = 0 THEN 'No registration of ' || cur.name || ' awaits approval.'
                 ELSE n_cur_regs || ' registration' || CASE WHEN n_cur_regs = 1 THEN '' ELSE 's' END || ' of ' || cur.name || ' still await approval.' END;
    END IF;
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
END $function$;

CREATE OR REPLACE FUNCTION finance.legacy_nelfund_stage(p_import uuid, p_rows jsonb)
 RETURNS TABLE(total_rows integer, staged integer, already_staged integer, skipped integer)
 LANGUAGE plpgsql
AS $function$
DECLARE r jsonb; n int := 0; ns int := 0; na int := 0; nk int := 0; v_id uuid; v_tx text; v_ref text; v_session text;
        v_actor uuid := nullif(current_setting('moaum.actor_id', true), '')::uuid;
BEGIN
    IF v_actor IS NULL THEN RAISE EXCEPTION 'LEGACY_ACTOR_REQUIRED: old-portal payments are staged by a person' USING ERRCODE = '23514'; END IF;
    IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN RAISE EXCEPTION 'LEGACY_ROWS_REQUIRED: the payments are rows' USING ERRCODE = '23514'; END IF;
    FOR r IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        n := n + 1;
        v_tx := nullif(btrim(coalesce(r ->> 'transactionId', '')), '');
        v_ref := nullif(btrim(coalesce(r ->> 'reference', '')), '');
        IF v_tx IS NULL AND v_ref IS NULL THEN nk := nk + 1; CONTINUE; END IF;
        IF EXISTS (SELECT 1 FROM finance.legacy_nelfund_payment p
                    WHERE (v_tx IS NOT NULL AND upper(p.source_transaction_id) = upper(v_tx)) OR (v_ref IS NOT NULL AND upper(p.source_reference) = upper(v_ref))) THEN
            na := na + 1; CONTINUE;
        END IF;
        -- the session the payment belongs to: the row's, else the one its date falls in; never the current one by default
        v_session := finance.legacy_session_of(r ->> 'session');
        IF v_session IS NULL AND finance.legacy_date(r ->> 'paidAt') IS NOT NULL THEN
            -- V400: the session current on the day it was paid (two sessions may overlap since V377)
            v_session := policy.session_current_on(finance.legacy_date(r ->> 'paidAt')::date);
        END IF;
        INSERT INTO finance.legacy_nelfund_payment (import_id, row_no, source_transaction_id, source_reference, source_student_id, matric_no, jamb_no, application_no,
                                                    student_name, amount, paid_at, paid_at_text, session, legacy_status, normalized_status, raw, imported_by)
        VALUES (p_import, coalesce((r ->> 'row')::int, n), v_tx, v_ref,
                nullif(btrim(coalesce(r ->> 'legacyStudentId', '')), ''), nullif(upper(btrim(coalesce(r ->> 'matric', ''))), ''), nullif(upper(btrim(coalesce(r ->> 'jamb', ''))), ''),
                nullif(upper(btrim(coalesce(r ->> 'applicationNo', ''))), ''), nullif(btrim(coalesce(r ->> 'name', '')), ''),
                nullif(regexp_replace(coalesce(r ->> 'amount', ''), '[^0-9.]', '', 'g'), '')::numeric,
                finance.legacy_date(r ->> 'paidAt'), nullif(btrim(coalesce(r ->> 'paidAt', '')), ''), v_session,
                nullif(btrim(coalesce(r ->> 'status', '')), ''), finance.legacy_status_of(coalesce(nullif(btrim(coalesce(r ->> 'status', '')), ''), 'success')), r, v_actor)
        RETURNING id INTO v_id;
        INSERT INTO finance.legacy_nelfund_reconciliation (payment_id, import_id) VALUES (v_id, p_import);
        ns := ns + 1;
    END LOOP;
    UPDATE finance.legacy_nelfund_import i SET total_rows = i.total_rows + n, staged = i.staged + ns, already_staged = i.already_staged + na, skipped = i.skipped + nk WHERE i.id = p_import;
    RETURN QUERY SELECT n, ns, na, nk;
END $function$;

COMMENT ON FUNCTION policy.transition_readiness(text) IS
  'The checks the transition into a planned session runs (V289): blocking ones stop it (exists, planned, Senate minute, begins after the current session began); advisory ones are shown and, for the automatic clock, also block; since V400 it also says what is still open in the session being completed, which never blocks.';

COMMIT;
