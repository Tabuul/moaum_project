-- V585: the migrated students' clearance figures read from a count kept for each student, and the Registry and the Bursary
-- told before a session starts automatically what its readiness still shows.
--
--   * The cleared gate pairs kept. clearance.migrated_summary (V577) read every clearance decision on the register — 2.85 million
--     on the live-shaped copy, 16–18 s — to count the migrated students who stand cleared at every unit. Each student's count of
--     gate pairs (a gate purpose at a unit) whose latest decision reads CLEARED is now kept in clearance.gate_pairs_kept, worked
--     out again for the students a write to clearance.item touches (statement triggers, the students' kept rows locked first so
--     two officers deciding at once are both counted), and for everyone when the gate purposes or the units change. The summary
--     reads the register and the kept counts; the figures are the old function's, in every level range.
--   * Told before the start. A week before a planned session's automatic transition date the holders of the Registrar's and the
--     Bursar's offices are told what its readiness shows (policy.tell_session_start, template SESSION_START_READINESS): whether it
--     will start on its own, every check not met, and what its fees and spillover lines stand at; again the day before while a
--     check is still not met. Once each, by event key.
--   * The Bursar's hold. finance.fee_setting.spill_lines_hold_start: the Bursar chooses whether spillover students with no
--     spillover line hold the automatic start (off by default, as V580 left it); policy.transition_readiness (restated from
--     V580's text) reads it.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'registrar', true);
SELECT set_config('moaum.reason', 'V585: migrated clearance figures kept, the start of a session warned of', true);

-- ── each student's cleared gate pairs, kept ────────────────────────────────────────────────────────────────────────────────
CREATE TABLE clearance.gate_pairs_kept (
    student_id uuid PRIMARY KEY REFERENCES people.student (id) ON DELETE CASCADE,
    cleared    integer NOT NULL DEFAULT 0,
    kept_at    timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE clearance.gate_pairs_kept IS
  'V585: for each student, the gate pairs (a gate purpose at a unit) whose latest decision reads CLEARED — kept by triggers on clearance.item';
SELECT audit.exempt('clearance.gate_pairs_kept', 'a count worked out from clearance.item on every write to it; the decisions themselves are on the audit spine');

-- the students given (everyone when NULL) counted again; a student's row locked first, so a decision another transaction is
-- making for the same student is waited for and counted (each statement after the lock reads what is committed)
CREATE FUNCTION clearance.keep_gate_pairs(p_students uuid[])
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE n integer;
BEGIN
    IF p_students IS NULL THEN
        DELETE FROM clearance.gate_pairs_kept;
        INSERT INTO clearance.gate_pairs_kept (student_id, cleared)
        SELECT l.student_id, count(*) FILTER (WHERE l.state = 'CLEARED')
          FROM (SELECT DISTINCT ON (c.student_id, c.purpose, c.unit) c.student_id, c.state
                  FROM clearance.item c
                  JOIN ref.clearance_purpose pu ON pu.code = c.purpose AND pu.gate
                  JOIN clearance.unit u ON u.code = c.unit
                 WHERE c.superseded_by IS NULL
                 ORDER BY c.student_id, c.purpose, c.unit, c.decided_at DESC) l
         GROUP BY l.student_id;
        GET DIAGNOSTICS n = ROW_COUNT;
        RETURN n;
    END IF;
    IF cardinality(p_students) = 0 THEN
        RETURN 0;
    END IF;
    INSERT INTO clearance.gate_pairs_kept (student_id)
    SELECT t.id FROM (SELECT DISTINCT unnest(p_students) AS id) t JOIN people.student s ON s.id = t.id ORDER BY t.id
    ON CONFLICT (student_id) DO NOTHING;
    PERFORM 1 FROM clearance.gate_pairs_kept k WHERE k.student_id = ANY (p_students) ORDER BY k.student_id FOR UPDATE;
    UPDATE clearance.gate_pairs_kept k
       SET cleared = (SELECT count(*) FROM (SELECT DISTINCT ON (c.purpose, c.unit) c.state
                                              FROM clearance.item c
                                              JOIN ref.clearance_purpose pu ON pu.code = c.purpose AND pu.gate
                                              JOIN clearance.unit u ON u.code = c.unit
                                             WHERE c.student_id = k.student_id AND c.superseded_by IS NULL
                                             ORDER BY c.purpose, c.unit, c.decided_at DESC) l
                       WHERE l.state = 'CLEARED'),
           kept_at = now()
     WHERE k.student_id = ANY (p_students);
    GET DIAGNOSTICS n = ROW_COUNT;
    RETURN n;
END $fn$;
COMMENT ON FUNCTION clearance.keep_gate_pairs(uuid[]) IS
  'V585: the students given (everyone when NULL) have their cleared gate pairs counted again into clearance.gate_pairs_kept';

CREATE FUNCTION clearance.gate_pairs_after_insert() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    PERFORM clearance.keep_gate_pairs(ARRAY(SELECT DISTINCT n.student_id FROM changed_new n));
    RETURN NULL;
END $fn$;
CREATE FUNCTION clearance.gate_pairs_after_update() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    PERFORM clearance.keep_gate_pairs(ARRAY(SELECT n.student_id FROM changed_new n UNION SELECT o.student_id FROM changed_old o));
    RETURN NULL;
END $fn$;
CREATE FUNCTION clearance.gate_pairs_after_delete() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    PERFORM clearance.keep_gate_pairs(ARRAY(SELECT DISTINCT o.student_id FROM changed_old o));
    RETURN NULL;
END $fn$;
CREATE TRIGGER trg_gate_pairs_insert AFTER INSERT ON clearance.item REFERENCING NEW TABLE AS changed_new
    FOR EACH STATEMENT EXECUTE FUNCTION clearance.gate_pairs_after_insert();
CREATE TRIGGER trg_gate_pairs_update AFTER UPDATE ON clearance.item REFERENCING OLD TABLE AS changed_old NEW TABLE AS changed_new
    FOR EACH STATEMENT EXECUTE FUNCTION clearance.gate_pairs_after_update();
CREATE TRIGGER trg_gate_pairs_delete AFTER DELETE ON clearance.item REFERENCING OLD TABLE AS changed_old
    FOR EACH STATEMENT EXECUTE FUNCTION clearance.gate_pairs_after_delete();

-- the gate purposes or the units changed: every student counted again (a rare act, and the count depends on both)
CREATE FUNCTION clearance.gate_pairs_after_gates() RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
    PERFORM clearance.keep_gate_pairs(NULL);
    RETURN NULL;
END $fn$;
CREATE TRIGGER trg_gate_pairs_purpose AFTER INSERT OR DELETE OR UPDATE OF gate, code ON ref.clearance_purpose
    FOR EACH STATEMENT EXECUTE FUNCTION clearance.gate_pairs_after_gates();
CREATE TRIGGER trg_gate_pairs_unit AFTER INSERT OR DELETE OR UPDATE OF code ON clearance.unit
    FOR EACH STATEMENT EXECUTE FUNCTION clearance.gate_pairs_after_gates();

SELECT clearance.keep_gate_pairs(NULL);

-- the summary reads the register and the kept counts (restated from V577: the same three figures)
CREATE OR REPLACE FUNCTION clearance.migrated_summary(p_from integer DEFAULT 100, p_to integer DEFAULT 400)
RETURNS TABLE(migrated bigint, cleared bigint, uncleared bigint)
LANGUAGE sql STABLE AS $fn$
    -- V577: a student stands cleared when every gate purpose at every unit reads CLEARED at its latest decision; V585: the CLEARED
    -- pairs each student holds are kept (clearance.gate_pairs_kept), so the decisions are not read here
    WITH need AS (SELECT count(*) AS n FROM ref.clearance_purpose pu CROSS JOIN clearance.unit u WHERE pu.gate)
    SELECT count(*), count(*) FILTER (WHERE coalesce(k.cleared, 0) >= need.n), count(*) FILTER (WHERE coalesce(k.cleared, 0) < need.n)
      FROM people.student s
      CROSS JOIN need
      LEFT JOIN clearance.gate_pairs_kept k ON k.student_id = s.id
     WHERE s.matric_no IS NOT NULL AND s.matriculation_run IS NULL
       AND s.current_level BETWEEN p_from AND p_to
       AND s.status NOT IN ('WITHDRAWN','EXPELLED','TRANSFERRED_OUT','DECEASED','GRADUATED')
$fn$;

-- ── the Bursar's hold on the automatic start ───────────────────────────────────────────────────────────────────────────────
ALTER TABLE finance.fee_setting
    ADD COLUMN spill_lines_hold_start boolean NOT NULL DEFAULT false,
    ADD COLUMN spill_hold_set_at timestamptz,
    ADD COLUMN spill_hold_set_by uuid;
COMMENT ON COLUMN finance.fee_setting.spill_lines_hold_start IS
  'V585: true when spillover students with no spillover line hold a session''s automatic start (the Bursar''s choice; a person may still start it)';

CREATE FUNCTION finance.set_spill_hold_start(p_hold boolean)
RETURNS boolean LANGUAGE plpgsql AS $fn$
BEGIN
    IF p_hold IS NULL THEN
        RAISE EXCEPTION 'FEE_SPILL_HOLD: say whether the spillover lines hold the automatic start' USING ERRCODE = '23514';
    END IF;
    UPDATE finance.fee_setting SET spill_lines_hold_start = p_hold, spill_hold_set_at = now(),
           spill_hold_set_by = nullif(current_setting('moaum.actor_id', true), '')::uuid
     WHERE id = 1;
    RETURN p_hold;
END $fn$;

-- ── the readiness reads the hold (restated from V580's text) ───────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION policy.transition_readiness(p_to text)
 RETURNS TABLE(code text, ok boolean, blocking boolean, detail text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE s policy.academic_session%ROWTYPE; cur policy.academic_session%ROWTYPE; n_sem int; n_dated int; n_fee int; n_fresh int; n_win int; n_cur_sem int; n_cur_sheets int; n_cur_regs int; n_spill_none bigint; n_spill_lines int; v_hold boolean;
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
    -- V580: the spillover students the session's fees charge nothing, by the basis in force — said, never holding the transition or
    -- the automatic clock (which a check not met would hold, V289), as the current session's open semesters are said.
    -- V585: unless the Bursar has chosen that they hold the automatic start (finance.fee_setting.spill_lines_hold_start); a person
    -- may still make the session current, as for any check that is not blocking
    SELECT coalesce(sum(g.students), 0) INTO n_spill_none FROM finance.fee_gaps(p_to) g WHERE g.spillover AND NOT g.stated;
    SELECT count(*) INTO n_spill_lines FROM finance.fee_schedule WHERE session = p_to AND spillover AND ended_at IS NULL;
    SELECT coalesce((SELECT g.spill_lines_hold_start FROM finance.fee_setting g WHERE g.id = 1), false) INTO v_hold;
    RETURN QUERY SELECT 'SPILLOVER_FEE_LINES', NOT v_hold OR n_spill_none = 0, false,
        CASE WHEN n_spill_none = 0 THEN 'Every spillover student is charged a spillover line for ' || p_to || ' (' || n_spill_lines || ' stated).'
             ELSE n_spill_none || ' spillover student' || CASE WHEN n_spill_none = 1 THEN ' has' ELSE 's have' END || ' no spillover line for ' || p_to
                  || ' (' || n_spill_lines || ' stated, charged ' || CASE finance.spill_basis() WHEN 'COHORT' THEN 'by the cohort' ELSE 'by the level' END
                  || '): state them, or copy the last session''s on the Fee Schedule.'
                  || CASE WHEN v_hold THEN ' The Bursar has chosen that this holds the automatic start until they are stated.' ELSE '' END END;
    SELECT count(*) INTO n_win FROM policy.portal_window WHERE session = p_to AND superseded_at IS NULL;
    RETURN QUERY SELECT 'PORTAL_WINDOWS', true, false,
        CASE WHEN n_win > 0 THEN n_win || ' portal window rule(s) are set for ' || p_to || '.' ELSE 'No portal window is configured for ' || p_to || '; school fees payment and course registration are open by default.' END;
    SELECT count(*) INTO n_fresh FROM people.student WHERE entry_session = p_to;
    RETURN QUERY SELECT 'FRESH_STUDENTS', true, false,
        CASE WHEN n_fresh > 0 THEN n_fresh || ' entrant(s) of ' || p_to || ' are on the register and continue under the same accounts.' ELSE 'No entrant of ' || p_to || ' is on the register yet.' END;
    RETURN QUERY SELECT 'RETURNING_STUDENTS', true, false,
        'Returning students are not moved by the transition: they progress by the results, promotion and roll-over rules that already exist.';
END $function$;

-- ── told before the start ──────────────────────────────────────────────────────────────────────────────────────────────────
INSERT INTO platform.notice_template (key, label, purpose, email_subject, email_body, sms_body, portal_title, portal_body, variables, mandatory, priority) VALUES
('SESSION_START_READINESS', 'A session starts automatically soon',
 'To the Registrar''s and the Bursar''s offices a week before a planned session''s automatic transition date, and the day before while a check is not met',
 '[SESSION] starts automatically [WHEN]: [OUTCOME_SHORT]',
 E'Dear [FIRST_NAME],\n\n[SESSION] is set to become the current session automatically on [DATE] ([WHEN]).\n\n[OUTCOME]\n\nFees: [FEES]\n\nThe readiness is on Academic Calendar → Session state; the fees on Fee Setup and Schedule: [PORTAL_URL]\n\nMOAUM Portal',
 NULL,
 '[SESSION] starts automatically [WHEN]',
 '[OUTCOME] Fees: [FEES]',
 ARRAY['FIRST_NAME','SESSION','DATE','WHEN','OUTCOME','OUTCOME_SHORT','FEES','PORTAL_URL','UNIVERSITY_SHORT'], false, 'HIGH');

-- each planned session set to start automatically within a week: the Registrar's and the Bursar's offices told what its readiness
-- shows — a week before (whatever it shows) and the day before (only while a check is not met), once each
CREATE FUNCTION policy.tell_session_start()
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date; s record; r record; d int; v_stage text; v_vars jsonb; v_not_met text;
        v_blocked int; v_held int; v_fees text; p record; v_told int := 0;
BEGIN
    FOR s IN SELECT a.name, a.transitions_on FROM policy.academic_session a
              WHERE a.state = 'PLANNED' AND a.transition_mode = 'AUTOMATIC' AND a.transitions_on BETWEEN v_today AND v_today + 7
              ORDER BY a.transitions_on LOOP
        d := s.transitions_on - v_today;
        -- the readiness read once: the checks not met (those that stop it outright first), and what the fees stand at
        v_not_met := NULL; v_blocked := 0; v_held := 0; v_fees := NULL;
        FOR r IN SELECT * FROM policy.transition_readiness(s.name) x ORDER BY x.blocking DESC, x.code LOOP
            IF NOT r.ok THEN
                v_not_met := coalesce(v_not_met || E'\n', '') || '• ' || r.detail;
                IF r.blocking THEN v_blocked := v_blocked + 1; ELSE v_held := v_held + 1; END IF;
            END IF;
            IF r.ok AND r.code IN ('FEE_SCHEDULE', 'SPILLOVER_FEE_LINES') THEN
                v_fees := coalesce(v_fees || ' ', '') || r.detail;
            END IF;
        END LOOP;
        v_stage := CASE WHEN d <= 1 THEN 'EVE' ELSE 'WEEK' END;
        CONTINUE WHEN v_stage = 'EVE' AND v_not_met IS NULL;
        v_vars := jsonb_build_object(
            'SESSION', s.name,
            'DATE', to_char(s.transitions_on, 'FMDay FMDD Mon YYYY'),
            'WHEN', CASE d WHEN 0 THEN 'today' WHEN 1 THEN 'tomorrow' ELSE 'in ' || d || ' days' END,
            'OUTCOME_SHORT', CASE WHEN v_not_met IS NULL THEN 'ready' ELSE (v_blocked + v_held) || ' check' || CASE WHEN v_blocked + v_held = 1 THEN '' ELSE 's' END || ' not met' END,
            'OUTCOME', CASE WHEN v_not_met IS NULL THEN 'Every check is met: it will start on its own that night.'
                            ELSE 'It will NOT start on its own while ' || CASE WHEN v_blocked + v_held = 1 THEN 'this check is' ELSE 'these checks are' END
                                 || ' not met' || CASE WHEN v_blocked > 0 THEN '' ELSE ' (the Registrar may still make it current from the calendar)' END
                                 || E':\n' || v_not_met END,
            'FEES', coalesce(v_fees, 'as above.'));
        FOR p IN SELECT DISTINCT oa.person_id FROM iam.office_assignment oa
                  WHERE oa.office_code IN ('registrar', 'bursar') AND oa.valid_from <= v_today AND (oa.valid_to IS NULL OR oa.valid_to >= v_today) LOOP
            v_told := v_told + platform.tell_person(p.person_id, 'SESSION_START_READINESS', NULL, v_vars,
                                                    'session-start:' || s.name || ':' || s.transitions_on || ':' || v_stage || ':' || p.person_id);
        END LOOP;
    END LOOP;
    RETURN v_told;
END $fn$;
COMMENT ON FUNCTION policy.tell_session_start() IS
  'V585: the Registrar''s and the Bursar''s offices told a week before a session''s automatic start (and the day before while a check is not met) what its readiness shows';

COMMIT;
