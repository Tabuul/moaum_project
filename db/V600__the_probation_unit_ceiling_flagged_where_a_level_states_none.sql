-- V600: the probation unit ceiling flagged where an undergraduate level states none.
--
--   * FR-REG-07 left one value unset: no level states policy.level_limit.probation_max_units on the live-shaped copy (nine level
--     limits, none with a ceiling), so a student on probation registers up to the level's maximum like everyone else. The value
--     is the University's; until it is set, the people who set up a session are told.
--   * policy.probation_ceiling_unset() names the undergraduate levels (100–600, where probation standing is reached) with no
--     ceiling. Session & Semester Setup says so under its level limits, and the warning sent a week before a session's automatic
--     start (policy.tell_session_start, V585's text) carries it as a line for attention — never a check not met: the start is
--     not held for it, and the day-before notice is not sent for it alone.

BEGIN;

SELECT set_config('moaum.actor_id', '00000000-0000-0000-0000-000000000000', true);
SELECT set_config('moaum.actor_office', 'registrar', true);
SELECT set_config('moaum.reason', 'V600: the probation unit ceiling flagged where a level states none', true);

CREATE FUNCTION policy.probation_ceiling_unset()
RETURNS integer[] LANGUAGE sql STABLE AS $fn$
    SELECT coalesce(array_agg(l.level ORDER BY l.level), '{}'::integer[])
      FROM policy.level_limit l
     WHERE l.level BETWEEN 100 AND 600 AND l.probation_max_units IS NULL
$fn$;
COMMENT ON FUNCTION policy.probation_ceiling_unset() IS
  'V600: the undergraduate levels (100–600) whose unit limit states no probation ceiling: a student on probation there registers up to the level''s maximum';

/* the levels as the notice says them: "100, 200 and 300 Level" */
CREATE FUNCTION policy.levels_words(p_levels integer[])
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
    SELECT CASE cardinality(coalesce(p_levels, '{}'))
               WHEN 0 THEN NULL
               WHEN 1 THEN p_levels[1] || ' Level'
               ELSE array_to_string(p_levels[1:cardinality(p_levels) - 1], ', ') || ' and ' || p_levels[cardinality(p_levels)] || ' Level' END
$fn$;

-- V585's text; the probation ceiling a line for attention in OUTCOME
CREATE OR REPLACE FUNCTION policy.tell_session_start()
RETURNS integer LANGUAGE plpgsql AS $fn$
DECLARE v_today date := (now() AT TIME ZONE 'Africa/Lagos')::date; s record; r record; d int; v_stage text; v_vars jsonb; v_not_met text;
        v_blocked int; v_held int; v_fees text; p record; v_told int := 0; v_unset integer[] := policy.probation_ceiling_unset(); v_note text;
BEGIN
    -- V600: never a check not met — the start is not held for it, and the day before is not told for it alone
    v_note := CASE WHEN cardinality(v_unset) > 0 THEN
        E'\n\nFor attention (this does not hold the start): no probation unit ceiling is set for ' || policy.levels_words(v_unset)
        || ', so a student on probation there registers up to the level''s maximum. It is set per level on Session & Semester Setup.' END;
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
                                 || E':\n' || v_not_met END || coalesce(v_note, ''),
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
  'V585: the Registrar''s and the Bursar''s offices told a week before a session''s automatic start (and the day before while a check is not met) what its readiness shows; V600: with a line for attention where an undergraduate level states no probation ceiling';

COMMIT;
